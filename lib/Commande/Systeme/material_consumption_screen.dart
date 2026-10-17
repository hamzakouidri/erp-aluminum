import 'selling_price_calculator.dart';

// ==========================================================================
// ملف: MaterialConsumptionScreen
// الوظيفة العامة: شاشة "الكمية والتكلفة" — تعرض جدول تفصيلي لكل مكونات النافذة
// (بروفيلات، زجاج، ستار/شتر، إكسسوارات) مع حساب التكلفة وسعر البيع، وتسمح
// بتبديل المكونات، تعديل الأسعار يدويًا، وتفعيل/تعطيل عناصر اختيارية (Kits...).
// ==========================================================================
import 'dart:math' as math; // لاستخدام math.max عند حساب سعر القطعة الواحدة
import 'dart:async';
import 'dart:convert';
import 'package:database_data/widgets/app_material.dart';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:database_data/sql_database.dart'; // كائن الوصول لقاعدة بيانات SQLite
import 'package:database_data/Commande/Systeme/model.dart'; // نموذج بيانات النافذة (WindowModel)
import 'package:database_data/Commande/Systeme/calculate_component.dart'; // منطق توليد قائمة المكونات (BOM)
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
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
  final bool autoCalculateAndSave;

  const MaterialConsumptionScreen({
    super.key,
    required this.model,
    this.autoCalculateAndSave = false,
  });

  @override
  State<MaterialConsumptionScreen> createState() =>
      _MaterialConsumptionScreenState();
}

class _BomSwapTarget {
  final String profileType;
  final String category;
  final AccessoryDrawingMode? drawingMode;
  final bool isFrame;
  final bool isSash;
  final bool isSideCover;
  final int? seriesId;
  final String? overrideKey;

  const _BomSwapTarget({
    required this.profileType,
    required this.category,
    this.drawingMode,
    this.isFrame = false,
    this.isSash = false,
    this.isSideCover = false,
    this.seriesId,
    this.overrideKey,
  });

  bool get isSpecialProfile => isFrame || isSash || isSideCover;
}

class _MaterialConsumptionScreenState extends State<MaterialConsumptionScreen> {
  bool _automaticCompletionStarted = false;

  // Keep the selected cap in memory while it is disabled.  Removing the
  // override is intentional: the cutting engine uses its presence to decide
  // whether the cap thickness must be deducted from every blade cut.
  Map<String, dynamic>? _disabledBladeEndCap;
  bool showCostPrice =
      true; // إظهار/إخفاء سعر التكلفة (TODO: لاحقًا يُربط بصلاحية المدير)
  final ScrollController _scrollController =
      ScrollController(); // للتحكم بتمرير الجدول أفقيًا ومعرفة موضع السكرول
  final ScrollController _pageScrollController = ScrollController();
  bool _isBottomBarExpanded = false; // هل شريط الإعدادات السفلي مفتوح أو مطوي
  bool _isFetchingDefaults = false;
  double _fetchProgress = 0.0;
  bool _hasFetchedDefaults = false;
  int? _lastBomColorId;
  List<BomItem> _visibleBomItems = const [];
  int _bomRefreshGeneration = 0;
  bool _isRefreshingVisibleBom = false;
  Timer? _modelRefreshDebounce;
  final List<Timer> _initialPriceRetryTimers = <Timer>[];
  StreamSubscription<String>? _dbUpdateSubscription;
  String _lastPriceContextSignature = '';
  final Map<String, double> _accessoryPriceCache = {};
  Map<String, double> _mainWarehouseStock = const {};
  Map<int, Map<String, dynamic>> _profileCalculationRules = {};

  // اختصار لجلب اللغة الحالية من الـ Provider بدون الاستماع لتغييراتها (listen:false)
  String get _lang {
    final language = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    // BomItem.getLocalizedName uses the stable short codes below.  Passing
    // AppLanguage.name ("french"/"english") silently fell through to Arabic.
    switch (language) {
      case AppLanguage.arabic:
        return 'ar';
      case AppLanguage.french:
        return 'fr';
      case AppLanguage.english:
        return 'en';
    }
  }

  String _canonicalStockType(String? value) {
    final normalized = (value ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[ _-]+'),
      '',
    );
    if (const {
      'profile',
      'profiles',
      'section',
      'sections',
    }.contains(normalized)) {
      return 'Section';
    }
    if (const {'accessory', 'accessories'}.contains(normalized)) {
      return 'Accessory';
    }
    if (const {'shuttercomponent', 'shuttercomponents'}.contains(normalized)) {
      return 'ShutterComponent';
    }
    if (const {'joint', 'joints'}.contains(normalized)) return 'Joints';
    if (normalized == 'glass') return 'Glass';
    return value?.trim() ?? '';
  }

  String _stockKey(String? itemType, int itemId, int? colorId) =>
      '${_canonicalStockType(itemType)}|$itemId|${colorId ?? 0}';

  int? _itemColorId(BomItem item) {
    final isAccessory =
        item.category == 'accessory' || item.category == 'other';
    final selectedColor = isAccessory
        ? widget.model.selectedAccessoryColor
        : widget.model.selectedDbColor;
    final value = item.colorId ?? selectedColor?['id'];
    return value is num ? value.toInt() : int.tryParse('${value ?? ''}');
  }

  double? _mainStockFor(BomItem item) {
    final id = item.catalogItemId;
    final type = item.inventoryItemType;
    if (id == null || type == null || type.trim().isEmpty) return null;
    final colorId = _itemColorId(item);
    return _mainWarehouseStock[_stockKey(type, id, colorId)] ??
        _mainWarehouseStock[_stockKey(type, id, null)];
  }

  Future<Map<String, double>> _loadMainWarehouseStock() async {
    final database = SqlDatabase();
    final sqlite = await database.db;
    if (sqlite == null) return const {};
    final rows = await sqlite.query('CurrentStock');
    final result = <String, double>{};
    for (final row in rows) {
      final rawItemId = row['item_id'];
      final itemId = rawItemId is num
          ? rawItemId.toInt()
          : int.tryParse('${rawItemId ?? ''}');
      if (itemId == null) continue;
      final rawColorId = row['color_id'];
      final colorId = rawColorId is num
          ? rawColorId.toInt()
          : int.tryParse('${rawColorId ?? ''}');
      final rawQuantity = row['quantity'];
      final quantity = rawQuantity is num
          ? rawQuantity.toDouble()
          : double.tryParse('${rawQuantity ?? ''}') ?? 0.0;
      final key = _stockKey(row['item_type']?.toString(), itemId, colorId);
      result[key] = (result[key] ?? 0.0) + quantity;
      // Also accumulate to general key (null color) so items with or without
      // explicit colors match seamlessly in consumption view.
      if (colorId != null && colorId != 0) {
        final totalKey = _stockKey(row['item_type']?.toString(), itemId, null);
        result[totalKey] = (result[totalKey] ?? 0.0) + quantity;
      }
    }
    return result;
  }

  String _localizedBomUnit(String unit, AppLanguage language) {
    final trimmed = unit.trim();
    if (trimmed.isEmpty) return trimmed;
    if (language == AppLanguage.french) {
      if (trimmed == 'بارة' || trimmed == 'قطاع') return 'bar';
      if (trimmed == 'متر') return 'm';
      if (trimmed == 'قطعة') return 'pièce';
      if (trimmed == 'طقم') return 'kit';
    } else if (language == AppLanguage.english) {
      if (trimmed == 'بارة' || trimmed == 'قطاع') return 'bar';
      if (trimmed == 'متر') return 'm';
      if (trimmed == 'قطعة') return 'pcs';
      if (trimmed == 'طقم') return 'kit';
    }
    return Localization.translate(trimmed, language);
  }

  // دالة مساعدة: تتحقق إذا كان النص يحتوي حروف عربية (لتقرير هل نعرض الاسم الثانوي أو لا)
  bool _hasArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  int? _catalogInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}'.trim());
  }

  int? _catalogSeriesId(Map<String, dynamic>? item) =>
      item == null ? null : _catalogInt(item['series_id']);

  String _bomRowSearchText(BomItem item) =>
      '${item.originalName} ${item.name} ${item.profileCode ?? ''}'
          .toLowerCase();

  String _catalogSearchText(Map<String, dynamic>? item) {
    if (item == null) return '';
    return '${item['code'] ?? ''} ${item['name'] ?? ''} ${item['type'] ?? ''}'
        .toLowerCase();
  }

  bool _bomRowMentionsCatalog(BomItem item, Map<String, dynamic>? catalog) {
    if (catalog == null) return false;
    final rowText = _bomRowSearchText(item);
    final code = '${catalog['code'] ?? ''}'.trim().toLowerCase();
    final name = '${catalog['name'] ?? ''}'.trim().toLowerCase();
    if (code.isNotEmpty && rowText.contains(code)) return true;
    return name.isNotEmpty && rowText.contains(name);
  }

  bool _textLooksSlidingProfile(String text) {
    final lower = text.toLowerCase();
    return const [
      'couliss',
      'sliding',
      '2rail',
      '3rail',
      '2 rail',
      '3 rail',
      'monorail',
      'galandage',
      'sash lateral',
      'sash central',
      'sash traverse',
      'chicane',
      'rail',
      'منزلق',
      'جرار',
      'كوليس',
      'جانبي',
      'وسطي',
      'سكة',
      'ريديكتور',
    ].any(lower.contains);
  }

  bool _textLooksOpeningProfile(String text) {
    final lower = text.toLowerCase();
    return const [
      'ouvrant',
      'battant',
      'opening',
      'mifsal',
      'paumelle',
      'hinge',
      'system ob',
      'demi ob',
      'مفتح',
      'فتح',
      'ظلفة',
      'مفصل',
      'مفاصل',
      'سيستم',
    ].any(lower.contains);
  }

  AccessoryDrawingMode? _drawingModeFromProfileText(String text) {
    if (_textLooksSlidingProfile(text)) return AccessoryDrawingMode.sliding;
    if (_textLooksOpeningProfile(text)) return AccessoryDrawingMode.opening;
    return null;
  }

  AccessoryDrawingMode? _drawingModeFromCatalogMap(Map<String, dynamic>? item) {
    if (item == null) return null;
    return _drawingModeFromProfileText(_catalogSearchText(item));
  }

  AccessoryDrawingMode? _profileDrawingModeForItem(
    BomItem item, {
    bool isFrame = false,
    bool isSash = false,
    bool isSideCover = false,
  }) {
    final rowText =
        '${item.originalName} ${item.selectorType ?? ''} ${item.roleKey ?? ''}'
            .toLowerCase();
    if (_containsAny(rowText, const [
      'bouchon batmo',
      'bochon batmo',
      'بوشون باتمو',
      'بوشون الباتمو',
    ])) {
      // Bouchon Batmo is an opening-system profile even when the same
      // drawing also contains sliding zones.
      return AccessoryDrawingMode.opening;
    }
    if (_containsAny(rowText, const ['batmo', 'باتمو'])) {
      // Batmo belongs to the opening series and is only valid for a pair of
      // opening sashes, even when the drawing also contains sliding zones.
      return AccessoryDrawingMode.opening;
    }
    if (rowText.contains('plinthe') || rowText.contains('بلانت')) {
      // A sash plinthe belongs to the opening sash catalogue even when the
      // drawing also contains sliding zones.
      return AccessoryDrawingMode.opening;
    }

    final rowMode = isSideCover
        ? null
        : _drawingModeFromProfileText(_bomRowSearchText(item));
    if (rowMode != null) return rowMode;

    if (isFrame) {
      // The BOM source series is authoritative for a frame. This protects
      // the quantity/cost table from an old generic name such as "Frame"
      // after the drawing has selected the sliding series.
      final sourceSeriesId = item.sourceSeriesId;
      final slidingSeriesId = widget.model.activeSlidingSeries?.id;
      final openingSeriesId = widget.model.activeSeries?.id;
      if (sourceSeriesId != null &&
          sourceSeriesId == slidingSeriesId &&
          sourceSeriesId != openingSeriesId) {
        return AccessoryDrawingMode.sliding;
      }
      if (_bomRowMentionsCatalog(item, widget.model.slidingFrameOverride)) {
        return AccessoryDrawingMode.sliding;
      }
      if (_bomRowMentionsCatalog(item, widget.model.frameOverride)) {
        return _drawingModeFromCatalogMap(widget.model.frameOverride) ??
            AccessoryDrawingMode.opening;
      }
      final activeFrameMode = _drawingModeFromCatalogMap(
        widget.model.activeFrameOverride,
      );
      if (activeFrameMode != null) return activeFrameMode;
      if (widget.model.usesSlidingPrimaryProfiles) {
        return AccessoryDrawingMode.sliding;
      }
    }

    if (isSash) {
      if (_bomRowMentionsCatalog(item, widget.model.slidingSashOverride)) {
        return AccessoryDrawingMode.sliding;
      }
      if (_bomRowMentionsCatalog(item, widget.model.sashOverride)) {
        return _drawingModeFromCatalogMap(widget.model.sashOverride) ??
            AccessoryDrawingMode.opening;
      }
      final slidingSashMode = _drawingModeFromCatalogMap(
        widget.model.slidingSashOverride,
      );
      if (slidingSashMode != null) return slidingSashMode;
    }

    if (isSideCover) {
      final sideCoverMode = _drawingModeFromCatalogMap(
        widget.model.sideCoverOverride,
      );
      if (sideCoverMode != null) return sideCoverMode;
      if (widget.model.usesSlidingPrimaryProfiles) {
        return AccessoryDrawingMode.sliding;
      }
    }

    final hasSlidingSash = widget.model.zones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpeningSash = widget.model.zones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );
    if (hasSlidingSash && !hasOpeningSash) {
      return AccessoryDrawingMode.sliding;
    }
    if (hasOpeningSash && !hasSlidingSash) {
      return AccessoryDrawingMode.opening;
    }

    if (widget.model.systemMode == 'sliding') {
      return AccessoryDrawingMode.sliding;
    }
    return null;
  }

  Map<String, dynamic>? _selectedProfileMapForTarget(
    BomItem item,
    AccessoryDrawingMode? mode, {
    bool isFrame = false,
    bool isSash = false,
    bool isSideCover = false,
  }) {
    if (isFrame) {
      if (mode == AccessoryDrawingMode.sliding) {
        return widget.model.slidingFrameOverride ??
            widget.model.activeFrameOverride;
      }
      if (_bomRowMentionsCatalog(item, widget.model.slidingFrameOverride)) {
        return widget.model.slidingFrameOverride;
      }
      return widget.model.frameOverride ?? widget.model.activeFrameOverride;
    }

    if (isSash) {
      if (mode == AccessoryDrawingMode.sliding) {
        return widget.model.slidingSashOverride;
      }
      if (_bomRowMentionsCatalog(item, widget.model.slidingSashOverride)) {
        return widget.model.slidingSashOverride;
      }
      return widget.model.sashOverride;
    }

    if (isSideCover) {
      return widget.model.sideCoverOverride;
    }

    return _componentOverrideForBom(item);
  }

  /// The BOM tells us which sash owns each hardware row.  This must take
  /// precedence over [WindowModel.systemMode], because a mixed PVC drawing
  /// has opening and sliding components at the same time.
  AccessoryDrawingMode? _accessoryDrawingModeForItem(BomItem item) {
    final name = _bomRowSearchText(item);
    if (item.category == 'profile') {
      return _profileDrawingModeForItem(item) ?? AccessoryDrawingMode.opening;
    }
    if (item.category != 'accessory' && item.category != 'other') return null;

    final isExplicitSliding = [
      'منزلق',
      'جرار',
      'كوليس',
      'كوريس',
      'couliss',
      'sliding',
      'roulette',
      'عجلات',
      'entrematique',
      'انتراميتيك',
    ].any(name.contains);
    if (isExplicitSliding) return AccessoryDrawingMode.sliding;

    final hasSlidingSash = widget.model.zones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpeningSash = widget.model.zones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );

    // All hinge rows and unqualified espagnolettes/window handles belong to
    // opening sashes.  Sliding alternatives carry an explicit sliding label.
    final isOpeningHardware = [
      'مفاصل',
      'hinges',
      'mifsal',
      'paumelle',
      'إسبانيوليت',
      'اسبانيوليت',
      'espagnolette',
      'مقبض نافذة',
      'المقبض (handle)',
      'poignée fenêtre',
      'poignee fenetre',
    ].any(name.contains);
    if (isOpeningHardware && (hasOpeningSash || !hasSlidingSash)) {
      return AccessoryDrawingMode.opening;
    }
    if (hasSlidingSash && !hasOpeningSash) {
      return AccessoryDrawingMode.sliding;
    }
    if (hasOpeningSash && !hasSlidingSash) {
      return AccessoryDrawingMode.opening;
    }
    return null;
  }

  int? _seriesIdForItem(BomItem item) {
    if (item.category == 'joint' &&
        ((item.roleKey ?? '').trim() == 'shutter_joint_brosse' ||
            (item.materialType ?? '').toLowerCase().trim() == 'shutter')) {
      return null;
    }
    final mode = _accessoryDrawingModeForItem(item);
    if (mode == AccessoryDrawingMode.sliding) {
      return widget.model.activeSlidingSeries?.id ??
          widget.model.activeSeries?.id ??
          item.sourceSeriesId;
    }
    if (mode == AccessoryDrawingMode.opening) {
      return widget.model.activeSeries?.id ?? item.sourceSeriesId;
    }
    final activeSeriesId = widget.model.systemMode == 'sliding'
        ? widget.model.activeSlidingSeries?.id
        : widget.model.activeSeries?.id;
    return activeSeriesId ?? item.sourceSeriesId;
  }

  String _materialTypeForItem(BomItem item) {
    final explicitMaterial = (item.materialType ?? '').toLowerCase().trim();
    if (explicitMaterial == 'pvc') return 'PVC';
    if (explicitMaterial == 'aluminium' ||
        explicitMaterial == 'aluminum' ||
        explicitMaterial == 'alu') {
      return 'Aluminium';
    }
    if (explicitMaterial == 'shutter') return 'Shutter';
    return _accessoryDrawingModeForItem(item) == AccessoryDrawingMode.sliding
        ? (widget.model.isSlidingPVC ? 'PVC' : 'Aluminium')
        : (widget.model.isPVC ? 'PVC' : 'Aluminium');
  }

  bool _containsAny(String value, Iterable<String> tokens) {
    final lower = value.toLowerCase();
    return tokens.any((token) => lower.contains(token.toLowerCase()));
  }

  bool _isScrewBomName(String name) {
    final lower = name.toLowerCase();
    return name.contains('براغي') ||
        name.contains('برغي') ||
        lower.contains('screw') ||
        lower.contains('vis');
  }

  bool _matchesDisplayedOverride(String text, Map<String, dynamic>? override) {
    if (override == null) return false;
    var display = '${override['code'] ?? ''} - ${override['name'] ?? ''}'
        .trim();
    if (display.startsWith('- ')) display = display.substring(2);
    return text == display;
  }

  Map<String, dynamic>? _componentOverrideForBom(BomItem item) {
    final primaryKey = item.overrideKey ?? item.originalName;
    final direct = widget.model.componentOverrides[primaryKey];
    if (direct is Map) return Map<String, dynamic>.from(direct);
    final fallback = widget.model.componentOverrides[item.originalName];
    return fallback is Map ? Map<String, dynamic>.from(fallback) : null;
  }

  Map<String, dynamic>? _profileCalculationRuleFor(BomItem item) {
    final id = item.catalogItemId;
    return id == null ? null : _profileCalculationRules[id];
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

  bool _isExcludedFromPricing(BomItem item) {
    if (item.category != 'profile') return false;
    final rule = _profileCalculationRuleFor(item);
    return rule?['exclude_from_pricing'] == 1 ||
        rule?['exclude_from_pricing'] == true;
  }

  double _pricedTotal(BomItem item) =>
      _isExcludedFromPricing(item) ? 0.0 : item.total;

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

  double? _actualUsedMetersFor(BomItem item) {
    final multiplier = _profileLinearMultiplier(item);
    if (item.category != 'profile' || !_profileUsesLinearMeter(item)) {
      return item.actualUsedMeters;
    }
    if (item.pieces != null && item.pieces!.isNotEmpty) {
      final total = item.pieces!.fold<double>(0.0, (sum, piece) => sum + piece);
      return total > 0 ? total * multiplier : null;
    }
    if (item.length != null && item.requiredQuantity > 0) {
      return (item.length! / 1000.0) * item.requiredQuantity * multiplier;
    }
    return null;
  }

  _BomSwapTarget _resolveBomSwapTarget(BomItem item) {
    final original = item.originalName;
    final lower = original.toLowerCase();
    var drawingMode = _accessoryDrawingModeForItem(item);
    final explicitCategory = item.selectorCategory?.trim();
    final explicitType = item.selectorType?.trim();
    if ((explicitCategory != null && explicitCategory.isNotEmpty) ||
        (explicitType != null && explicitType.isNotEmpty)) {
      final type = explicitType == null || explicitType.isEmpty
          ? original
          : explicitType;
      final category = explicitCategory == null || explicitCategory.isEmpty
          ? item.category
          : explicitCategory;
      final isExplicitFrame = category == 'profile' && type == 'frame';
      final isExplicitSash = category == 'profile' && type == 'sash';
      final isExplicitSideCover = category == 'profile' && type == 'side_cover';
      final originalLooksPlinthe =
          lower.contains('plinthe') || lower.contains('بلانت');
      final isExplicitPlinthe =
          category == 'profile' &&
          (originalLooksPlinthe ||
              type.toLowerCase() == 'plant' ||
              type.toLowerCase().contains('plinthe') ||
              type.contains('بلانت'));
      if (isExplicitFrame || isExplicitSash || isExplicitSideCover) {
        drawingMode = _profileDrawingModeForItem(
          item,
          isFrame: isExplicitFrame,
          isSash: isExplicitSash,
          isSideCover: isExplicitSideCover,
        );
      }
      if (isExplicitPlinthe) {
        drawingMode = AccessoryDrawingMode.opening;
      }
      return _BomSwapTarget(
        profileType: isExplicitPlinthe ? 'plant' : type,
        category: category,
        drawingMode: drawingMode,
        isFrame: isExplicitFrame,
        isSash: isExplicitSash,
        isSideCover: isExplicitSideCover,
        seriesId: _seriesIdForItem(item),
        overrideKey: isExplicitPlinthe
            ? 'بلانت (Plinthe)'
            : item.overrideKey ?? original,
      );
    }

    final isFrame =
        original == 'الإطار (Frame)' ||
        original == 'الإطار (Cadre)' ||
        _matchesDisplayedOverride(original, widget.model.frameOverride) ||
        _matchesDisplayedOverride(original, widget.model.slidingFrameOverride);
    if (isFrame) {
      drawingMode = _profileDrawingModeForItem(item, isFrame: true);
      final selectedMap = _selectedProfileMapForTarget(
        item,
        drawingMode,
        isFrame: true,
      );
      return _BomSwapTarget(
        profileType: 'frame',
        category: 'profile',
        drawingMode: drawingMode,
        isFrame: true,
        seriesId:
            _catalogSeriesId(selectedMap) ??
            (drawingMode == AccessoryDrawingMode.sliding
                ? widget.model.activeSlidingSeries?.id
                : widget.model.activeSeries?.id),
      );
    }

    final isSash =
        original == 'الظلفة (Sash)' ||
        original == 'الظلفة المنزلقة (Sliding Sash)' ||
        lower.contains('sliding sash') ||
        _matchesDisplayedOverride(original, widget.model.sashOverride) ||
        _matchesDisplayedOverride(original, widget.model.slidingSashOverride);
    if (isSash) {
      drawingMode = _profileDrawingModeForItem(item, isSash: true);
      final selectedMap = _selectedProfileMapForTarget(
        item,
        drawingMode,
        isSash: true,
      );
      return _BomSwapTarget(
        profileType: 'sash',
        category: 'profile',
        drawingMode: drawingMode,
        isSash: true,
        seriesId:
            _catalogSeriesId(selectedMap) ??
            (drawingMode == AccessoryDrawingMode.sliding
                ? widget.model.activeSlidingSeries?.id
                : widget.model.activeSeries?.id),
      );
    }

    final isSideCover =
        original == 'الغطاء الجانبي (Side Cover)' ||
        _matchesDisplayedOverride(original, widget.model.sideCoverOverride);
    if (isSideCover) {
      drawingMode = _profileDrawingModeForItem(item, isSideCover: true);
      final selectedMap = _selectedProfileMapForTarget(
        item,
        drawingMode,
        isSideCover: true,
      );
      return _BomSwapTarget(
        profileType: 'side_cover',
        category: 'profile',
        drawingMode: drawingMode,
        isSideCover: true,
        seriesId:
            _catalogSeriesId(selectedMap) ??
            (drawingMode == AccessoryDrawingMode.sliding
                ? widget.model.activeSlidingSeries?.id
                : widget.model.activeSeries?.id),
      );
    }

    if (_containsAny(original, const ['جوان', 'joint'])) {
      final isShutterJoint = _containsAny(original.toLowerCase(), const [
        'للستار',
        'shutter',
        'volet',
      ]);
      final explicitJointRole = item.roleKey?.trim();
      return _BomSwapTarget(
        profileType: explicitJointRole != null && explicitJointRole.isNotEmpty
            ? explicitJointRole
            : isShutterJoint
            ? 'Joint bross shutter'
            : _containsAny(original, const ['بروس', 'bross'])
            ? 'Joint bross'
            : original,
        category: 'joint',
        drawingMode: drawingMode,
        seriesId: isShutterJoint ? null : item.sourceSeriesId,
      );
    }

    if (_containsAny(original, const [
      'clamp',
      'clam',
      'كلامب',
      'كلام',
      'كلان',
    ])) {
      return _BomSwapTarget(
        profileType: 'clamp',
        category: 'accessory',
        drawingMode: drawingMode,
      );
    }

    if (original.contains('براغي')) {
      final type = switch (original) {
        final s when s.contains('براغي حديد الدعم') => 'is_renfort_screw',
        final s when s.contains('براغي بوشون باتمو') =>
          'is_bouchon_batmo_screw',
        final s when s.contains('براغي الباتمو') => 'is_batmo_screw',
        final s when s.contains('براغي الكيت') => 'is_kit_screw',
        final s when s.contains('براغي المانيفال') => 'is_manivelle_screw',
        final s when s.contains('براغي المحرك') => 'is_moteur_screw',
        final s when s.contains('براغي الصندوق') => 'is_caisson_screw',
        final s when s.contains('براغي التجميع') => 'is_assembly_screw',
        final s when s.contains('براغي التركيب') => 'is_installation_screw',
        final s when s.contains('براغي الإكسسوارات') => 'is_accessory_screw',
        _ => 'is_accessory_screw',
      };
      return _BomSwapTarget(
        profileType: type,
        category: 'accessory',
        drawingMode: drawingMode,
      );
    }

    if (item.category == 'accessory' || item.category == 'other') {
      var type = original;
      if (_containsAny(original, const ['قاش دوبل', 'Gache Double'])) {
        type = 'is_gache_double';
      } else if (_containsAny(original, const ['قاش سامبل', 'Gache Simple'])) {
        type = 'is_gache_simple';
      } else if (_containsAny(original, const [
        'قاش بورت',
        'Gache Porte',
        'Gâche Porte',
      ])) {
        type = 'is_gache_porte';
      } else if (_containsAny(original, const [
        'كاش كوليسون',
        'gache coulisse',
        'gâche coulisse',
        'gache coulissant',
        'gâche coulissant',
      ])) {
        type = 'كاش كوليسون';
      } else if (_containsAny(original, const [
        'poignée coulissante',
        'poignee coulissante',
        'مقبض منزلق',
      ])) {
        type = 'poignee coulissante';
      } else if (original.contains('مقبض الباب (Poignée Porte à Clé)')) {
        type = 'is_poign_clef';
      } else if (original.contains('مقبض الباب Condamnation')) {
        type = 'is_poign_condamnation';
      } else if (_containsAny(original, const ['الأسطوانة', 'Canon'])) {
        type = 'is_canon';
      } else if (_containsAny(original, const ['قفل بمفتاح', 'Clef'])) {
        type = 'is_lock_clef';
      } else if (_containsAny(original, const [
        'Serrure Condamnation',
        'قفل الباب Condamnation',
        'Condamnation',
      ])) {
        type = 'is_lock_condamnation';
      } else if (_containsAny(original, const ['قفل الباب', 'Serrure'])) {
        type = 'is_lock_clef';
      } else if (_containsAny(original, const ['اسبانيوليت', 'إسبانيوليت'])) {
        type = 'اسبانيوليت';
      } else if (_containsAny(original, const ['مفاصل', 'Hinges'])) {
        type = 'مفاصل';
      } else if (_containsAny(original, const ['فيرو', 'Verrou']) &&
          !original.contains('Central')) {
        type = 'فيرو';
      } else if (_containsAny(original, const [
        'تراينغل',
        'تريانغل',
        'Tringle',
        'Tangle',
        'Triangle',
      ])) {
        type = 'tringle';
      } else if (_containsAny(original, const ['كيت', 'kit'])) {
        type = 'kit';
        drawingMode ??= AccessoryDrawingMode.sliding;
      } else if (_containsAny(original, const [
        'المقبض (Handle)',
        'مقبض نافذة',
        'poignée fenêtre',
        'poignee fenetre',
      ])) {
        type = 'is_window_handle';
      } else if (_containsAny(original, const ['مقبض', 'Handle', 'Poignée'])) {
        type = 'مقبض';
      } else if (_containsAny(original, const ['الطاسو', 'tasso'])) {
        type = 'tasso';
      } else if (_containsAny(original, const ['عجلات', 'roulette'])) {
        type = 'roulette';
      } else if (_containsAny(original, const [
        'أونتروماتيك',
        'Entrematique',
        'انتراميتيك',
        'intra',
      ])) {
        type = 'entrematique';
      }
      return _BomSwapTarget(
        profileType: type,
        category: 'accessory',
        drawingMode: drawingMode,
      );
    }

    if (item.category == 'profile') {
      var type = original;
      final selectedMap = _selectedProfileMapForTarget(item, drawingMode);
      if (_containsAny(original, const [
        'renfort',
        'renfore',
        'الدعم',
        'حديد',
      ])) {
        type = 'renfort';
      } else if (_containsAny(original, const [
        'sash traverse',
        'سكة الظلفة',
        'traverse haut',
        'traverse bas',
      ])) {
        type = 'sash_traverse';
      } else if (_containsAny(original, const ['traverse', 'التقسيم'])) {
        type = 'mullion';
      } else if (_containsAny(original, const ['bouchon', 'بوشون', 'bochon'])) {
        type = 'bouchon batmo';
      } else if (_containsAny(original, const ['batmo', 'باتمو'])) {
        type = 'batmo';
      } else if (_containsAny(original, const [
        'reducteur',
        'réducteur',
        'ريديكتور',
        'مخفض',
      ])) {
        type = '67114';
      } else if (_containsAny(original, const [
        'parclose',
        'باكيت',
        'بيركلوز',
      ])) {
        type = 'parclose';
      } else if (_containsAny(original, const ['rail', 'الري', 'سكة'])) {
        type = 'rail';
      }
      return _BomSwapTarget(
        profileType: type,
        category: 'profile',
        drawingMode: drawingMode,
        seriesId:
            _catalogSeriesId(selectedMap) ??
            (drawingMode == AccessoryDrawingMode.sliding
                ? widget.model.activeSlidingSeries?.id
                : widget.model.activeSeries?.id),
      );
    }

    if (item.category == 'shutter') {
      var type = original;
      if (_containsAny(original, const ['مانيفال', 'manivelle'])) {
        type = 'مانيفال';
      } else if (_containsAny(original, const ['محرك', 'moteur'])) {
        type = 'محرك';
      } else if (_containsAny(original, const ['صندوق', 'caisson'])) {
        type = 'صندوق';
      } else if (_containsAny(original, const ['كيت', 'kit'])) {
        type = 'كيت';
      } else if (_containsAny(original, const ['سكك', 'coulisse'])) {
        type = 'سكك';
      } else if (_containsAny(original, const [
        'lame finale',
        'النهائية',
        'نهائية',
      ])) {
        type = 'شريحة نهائية';
      } else if (_containsAny(original, const ['شرائح', 'lame'])) {
        type = 'شريحة';
      } else if (_containsAny(original, const ['محور', 'axe'])) {
        type = 'محور';
      } else if (_containsAny(original, const ['أطاش', 'attache'])) {
        type = 'أطاش';
      } else if (_containsAny(original, const [
        'سيبور موتور',
        'support_moteur',
        'support moteur',
      ])) {
        type = 'سيبور موتور';
      } else if (_containsAny(original, const ['الامبو', 'embout'])) {
        type = 'الامبو';
      } else if (_containsAny(original, const [
        'سيبور رولمو',
        'support_roulement',
        'support roulement',
      ])) {
        type = 'سيبور رولمو';
      } else if (_containsAny(original, const [
        'أغطية الشفرات',
        'bouchons lames',
        'bouchon lame',
      ])) {
        type = 'أغطية الشفرات';
      }
      return _BomSwapTarget(
        profileType: type,
        category: 'shutter',
        drawingMode: drawingMode,
      );
    }

    return _BomSwapTarget(
      profileType: original,
      category: item.category,
      drawingMode: drawingMode,
    );
  }

  bool _swapSelectionNeedsDefaultRefresh(BomItem item, _BomSwapTarget target) {
    if (target.category != 'shutter') return false;
    return _containsAny(item.originalName, const [
      'الشرائح',
      'Lames',
      'السكك',
      'Coulisses',
      'الشريحة النهائية',
      'Lame Finale',
      'المحرك',
      'Moteur',
      'الصندوق',
      'Caisson',
      'كيت',
      'Kit',
    ]);
  }

  int? _seriesIdForSwapTarget(BomItem item, _BomSwapTarget target) {
    if (target.drawingMode == AccessoryDrawingMode.sliding) {
      return widget.model.activeSlidingSeries?.id ??
          widget.model.activeSeries?.id ??
          target.seriesId;
    }
    if (target.drawingMode == AccessoryDrawingMode.opening) {
      return widget.model.activeSeries?.id ?? target.seriesId;
    }
    final activeSeriesId = widget.model.systemMode == 'sliding'
        ? widget.model.activeSlidingSeries?.id
        : widget.model.activeSeries?.id;
    return activeSeriesId ?? target.seriesId ?? _seriesIdForItem(item);
  }

  String _materialTypeForSwapTarget(BomItem item, _BomSwapTarget target) {
    if (target.drawingMode == AccessoryDrawingMode.sliding) {
      return widget.model.isSlidingPVC ? 'PVC' : 'Aluminium';
    }
    if (target.drawingMode == AccessoryDrawingMode.opening) {
      return widget.model.isPVC ? 'PVC' : 'Aluminium';
    }
    return _materialTypeForItem(item);
  }

  bool _overrideLooksResolved(Object? value) {
    if (value is! Map) return false;
    final rawId = value['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse('${rawId ?? ''}'.trim()) ?? 0;
    if (id > 0) return true;
    return '${value['code'] ?? ''}'.trim().isNotEmpty ||
        '${value['name'] ?? ''}'.trim().isNotEmpty;
  }

  bool _bomItemHasResolvedSelection(BomItem item) {
    final catalogId = item.catalogItemId ?? 0;
    if (catalogId > 0) return true;

    final target = _resolveBomSwapTarget(item);
    if (target.isFrame) {
      if (target.drawingMode == AccessoryDrawingMode.sliding) {
        return _overrideLooksResolved(widget.model.slidingFrameOverride);
      }
      if (target.drawingMode == AccessoryDrawingMode.opening) {
        return _overrideLooksResolved(widget.model.frameOverride);
      }
      return _overrideLooksResolved(widget.model.frameOverride) ||
          _overrideLooksResolved(widget.model.slidingFrameOverride);
    }

    if (target.isSash) {
      if (target.drawingMode == AccessoryDrawingMode.sliding) {
        return _overrideLooksResolved(widget.model.slidingSashOverride);
      }
      if (target.drawingMode == AccessoryDrawingMode.opening) {
        return _overrideLooksResolved(widget.model.sashOverride);
      }
      return _overrideLooksResolved(widget.model.sashOverride) ||
          _overrideLooksResolved(widget.model.slidingSashOverride);
    }

    if (target.isSideCover) {
      return _overrideLooksResolved(widget.model.sideCoverOverride);
    }

    if (_overrideLooksResolved(_componentOverrideForBom(item))) {
      return true;
    }

    if (item.originalName.contains('قائم جانبي') ||
        item.originalName.contains('Sash Lateral')) {
      return _overrideLooksResolved(
            widget.model.componentOverrides['قائم جانبي (Sash Lateral)'],
          ) ||
          _overrideLooksResolved(
            widget
                .model
                .componentOverrides['قائم جانبي معزز (Sash Lateral Renforcé)'],
          ) ||
          _overrideLooksResolved(
            widget.model.componentOverrides['قائم جانبي (Lateral)'],
          );
    }

    if (item.originalName.contains('قائم وسطي') ||
        item.originalName.contains('Sash Central')) {
      return _overrideLooksResolved(
            widget.model.componentOverrides['قائم وسطي (Sash Central)'],
          ) ||
          _overrideLooksResolved(
            widget
                .model
                .componentOverrides['قائم وسطي معزز (Sash Central Renforcé)'],
          ) ||
          _overrideLooksResolved(
            widget.model.componentOverrides['قائم وسطي (Central)'],
          );
    }

    return false;
  }

  int? _selectedAccessoryColorId() {
    final rawId = widget.model.selectedAccessoryColor?['id'];
    return rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
  }

  /// Accessories may keep their real selling price in AccessoryColorPrices
  /// while their base price remains zero. Use the accessory colour selected in
  /// the drawing. A colourless accessory uses its base price and must not
  /// inherit the profile colour.
  Future<double> _resolveSelectedAccessoryPrice(
    Database database,
    Map<String, dynamic> accessory,
  ) async {
    final rawId = accessory['id'];
    final accessoryId = rawId is num
        ? rawId.toInt()
        : int.tryParse('${rawId ?? ''}');
    final colorId = _selectedAccessoryColorId();
    final cacheKey = '${accessoryId ?? 'none'}:${colorId ?? 'none'}';
    final canCachePrice = accessoryId != null;
    final cachedPrice = canCachePrice ? _accessoryPriceCache[cacheKey] : null;
    if (cachedPrice != null) return cachedPrice;

    if (accessoryId != null && colorId != null) {
      final colorRows = await database.query(
        'AccessoryColorPrices',
        columns: const ['price'],
        where: 'accessory_id = ? AND color_id = ?',
        whereArgs: [accessoryId, colorId],
        limit: 1,
      );
      if (colorRows.isNotEmpty) {
        final colorPrice = _safeDouble(colorRows.first['price']);
        if (colorPrice > 0) {
          if (canCachePrice) _accessoryPriceCache[cacheKey] = colorPrice;
          return colorPrice;
        }
      }
    }

    var price = _safeDouble(accessory['price_dzd'] ?? accessory['price']);
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (settings.applyPurchasePricesToCostTable && accessoryId != null) {
      final purchasePrice = await SqlDatabase().getLatestPurchasePrice(
        itemId: accessoryId,
        itemType: 'Accessories',
        colorId: colorId,
      );
      if (purchasePrice != null && purchasePrice >= 0) {
        price = purchasePrice;
      }
    }
    if (canCachePrice) _accessoryPriceCache[cacheKey] = price;
    return price;
  }

  // ------------------ إعدادات التسعير (تُحمَّل من SharedPreferences وقاعدة البيانات) ------------------
  double _profitMargin = 0.0; // نسبة الربح % (طريقة الحساب بالنسبة المئوية)
  double _pricePerSqm = 0.0; // سعر المتر المربع (طريقة الحساب بالمتر المربع)
  double _torqueFactor =
      1.5; // معامل عزم المحرك (لحساب قوة المحرك المطلوبة حسب وزن الستار)
  double _pricePerLinearMeterFromDb =
      0.0; // سعر المتر الخطي القادم من جدول Series في قاعدة البيانات
  double?
  _pricePerLinearMeterOverride; // تعديل يدوي لسعر المتر الخطي (يتجاوز القيمة من قاعدة البيانات)
  double _shutterSqmPriceFromDb =
      0.0; // سعر متر مربع الستار من جدول ShutterSqmPrices
  double? _shutterSqmPriceOverride; // تعديل يدوي لسعر متر الستار
  double _moustiquaireSqmPriceFromDb = 0.0;
  int _priceLoadGeneration = 0;
  double _moteurInstallFee = 0.0; // أجرة تركيب المحرك
  double _obInstallFee = 0.0; // أجرة تركيب System OB
  double _demiObInstallFee = 0.0; // أجرة تركيب Demi System OB
  double _verrouInstallFee = 0.0; // أجرة تركيب Verrou Central
  CostMethod _costMethod = CostMethod
      .percentage; // طريقة احتساب سعر البيع الحالية (نسبة/متر مربع/متر خطي)
  bool get _isShutterOnlyPricing => widget.model.isShutterOnly;
  Map<String, List<Map<String, dynamic>>> _kitBundleData =
      {}; // بيانات حزم الكيت (Kit Bundles) المحمّلة من القاعدة
  Map<String, bool> _kitPerLeafMap =
      {}; // يحدد لكل كيت هل الكمية تُحسب لكل ضلفة (per leaf) أو لا
  Map<String, double> _kitBundlePrices =
      {}; // أسعار الكيت من كتالوج الستائر (وليس من صفحة تركيب الكيت)
  Map<String, Map<String, dynamic>> _kitBundleMetadata = {};
  final Map<String, bool> _kitGroupExpanded =
      {}; // حالة توسعة/طي كل مجموعة كيت في الجدول
  final Map<String, List<String>> _manualTableOrder = {};

  bool get _desktopTableMode => MediaQuery.sizeOf(context).width >= 900;

  void _handleTablePageWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        !_pageScrollController.hasClients) {
      return;
    }
    // Only claim the wheel when the page can still move; at an edge the
    // event must stay available to the table or another scrollable.
    final current = _pageScrollController.position;
    if (!current.hasContentDimensions) return;
    final target = (current.pixels + event.scrollDelta.dy).clamp(
      current.minScrollExtent,
      current.maxScrollExtent,
    );
    if ((target - current.pixels).abs() < 0.5) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !_pageScrollController.hasClients) return;
      final position = _pageScrollController.position;
      if (!position.hasContentDimensions) return;
      final newOffset = (position.pixels + event.scrollDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((newOffset - position.pixels).abs() >= 0.5) {
        position.pointerScroll(event.scrollDelta.dy);
      }
    });
  }

  bool _isBouchonLameBomItem(BomItem item) =>
      item.originalName.contains('أغطية الشفرات') ||
      item.originalName.toLowerCase().contains('bouchons lames') ||
      item.originalName.toLowerCase().contains('bouchon lame');

  String _tableSectionForItem(BomItem item) {
    if (item.category == 'profile') return 'profile';
    if (item.category == 'joint') return 'joint';
    if (item.category == 'glass' || item.category == 'panneau') {
      return 'glass';
    }
    if (item.category == 'shutter' || _isBouchonLameBomItem(item)) {
      return 'shutter';
    }
    return 'accessory';
  }

  String _materialRowKey(BomItem item) => [
    item.category,
    item.kitGroupName ?? '',
    item.originalName,
    item.name,
    item.unit,
    item.catalogItemId ?? '',
  ].join('|');

  String _materialDragId(BomItem item) =>
      '${_tableSectionForItem(item)}\u0000${_materialRowKey(item)}';

  List<BomItem> _orderedMaterialItems(String section, List<BomItem> items) {
    final byKey = <String, BomItem>{
      for (final item in items) _materialRowKey(item): item,
    };
    final stored = _manualTableOrder[section] ?? const <String>[];
    final used = <String>{};
    final ordered = <BomItem>[];
    for (final key in stored) {
      final item = byKey[key];
      if (item != null && used.add(key)) ordered.add(item);
    }
    for (final item in items) {
      final key = _materialRowKey(item);
      if (used.add(key)) ordered.add(item);
    }
    return ordered;
  }

  void _moveMaterialRow(String sourceId, String targetId) {
    final sourceSeparator = sourceId.indexOf('\u0000');
    final targetSeparator = targetId.indexOf('\u0000');
    if (sourceSeparator <= 0 || targetSeparator <= 0) return;
    final sourceSection = sourceId.substring(0, sourceSeparator);
    final targetSection = targetId.substring(0, targetSeparator);
    if (sourceSection != targetSection) return;
    final sourceKey = sourceId.substring(sourceSeparator + 1);
    final targetKey = targetId.substring(targetSeparator + 1);
    final sectionItems = _visibleBomItems
        .where((item) => _tableSectionForItem(item) == sourceSection)
        .toList();
    final source = sectionItems.firstWhere(
      (item) => _materialRowKey(item) == sourceKey,
      orElse: () => sectionItems.first,
    );
    final target = sectionItems.firstWhere(
      (item) => _materialRowKey(item) == targetKey,
      orElse: () => sectionItems.first,
    );
    // Keep a kit's children together and allow independent rows to be
    // reordered among themselves.  This prevents a child from visually
    // escaping its kit group.
    if ((source.kitGroupName ?? '') != (target.kitGroupName ?? '')) return;
    final keys = _orderedMaterialItems(
      sourceSection,
      sectionItems,
    ).map(_materialRowKey).toList();
    final oldIndex = keys.indexOf(sourceKey);
    final targetIndex = keys.indexOf(targetKey);
    if (oldIndex < 0 || targetIndex < 0 || oldIndex == targetIndex) return;
    final moved = keys.removeAt(oldIndex);
    keys.insert(targetIndex, moved);
    setState(() => _manualTableOrder[sourceSection] = keys);
  }

  Widget _buildDraggableMaterialRow(BomItem item) {
    if (!_desktopTableMode) return _row(item);
    final dragId = _materialDragId(item);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != dragId,
      onAcceptWithDetails: (details) => _moveMaterialRow(details.data, dragId),
      builder: (context, candidates, rejected) {
        final isTarget = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: isTarget
              ? BoxDecoration(
                  border: Border.all(color: Colors.lightBlue, width: 2),
                )
              : null,
          child: LongPressDraggable<String>(
            data: dragId,
            axis: Axis.vertical,
            feedback: Material(
              color: Colors.transparent,
              elevation: 8,
              child: SizedBox(width: _minW, child: _row(item)),
            ),
            childWhenDragging: Opacity(opacity: 0.28, child: _row(item)),
            child: Stack(
              children: [
                _row(item),
                const PositionedDirectional(
                  top: 0,
                  end: 2,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 22,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Returns true only for bundles that belong to a shutter assembly.  Kit
  /// Bundles also stores window hardware (System OB, Verrou Central, ...),
  /// which must never appear in the shutter-kit selector.
  bool _isShutterKitBundle(Map<String, dynamic> kit) {
    final code = normalizeKitDescriptionCode(kit['description']);
    if (const {'V', 'M', 'MT', 'CT'}.contains(code)) return true;
    if (const {'OB', 'VC'}.contains(code) || code.startsWith('OB')) {
      return false;
    }
    final text = '${kit['name'] ?? ''} ${kit['description'] ?? ''}'
        .toLowerCase();
    final isOtherSystemKit =
        text.contains('system ob') ||
        text.contains('system_ob') ||
        text.contains('demi ob') ||
        text.contains('demi_ob') ||
        text.contains('verrou') ||
        text.contains('central') ||
        text.contains('أوبي') ||
        text.contains('نصف أوبي') ||
        text.contains('فيرو');
    if (isOtherSystemKit) return false;

    return text.contains('kit volet') ||
        text.contains('kit shutter') ||
        text.contains('kit manivelle') ||
        text.contains('kit sangle') ||
        text.contains('كيت فولي') ||
        text.contains('كيت الستار') ||
        text.contains('كيت مانيفال') ||
        text.contains('كيت مانيفر') ||
        text.contains('كيت حزام');
  }

  /// The kit definition and the kit selling price live in two different
  /// places: KitBundles holds its contents, while ShutterComponents holds the
  /// product named identically with component_type = "kit".  Read the latter
  /// so a kit never inherits the sum/cost of the items inside it.
  Future<double?> _readShutterKitPrice(
    Database database,
    String kitName,
  ) async {
    // Check KitBundles table first (set via PriceManagementScreen)
    final bundleRows = await database.query(
      'KitBundles',
      where: 'LOWER(TRIM(name)) = LOWER(TRIM(?))',
      whereArgs: [kitName],
      limit: 1,
    );
    if (bundleRows.isNotEmpty) {
      final bPrice = (bundleRows.first['price'] as num?)?.toDouble() ?? 0.0;
      if (bPrice > 0) return bPrice;
    }

    var catalogRows = await database.query(
      'ShutterComponents',
      // ShutterComponents has only the canonical `price` column.  Do not
      // project optional UI fields here: SQLite would fail the whole BOM load
      // when an older database does not contain them.
      columns: const ['id', 'price'],
      where:
          "LOWER(TRIM(name)) = LOWER(TRIM(?)) AND LOWER(TRIM(component_type)) = 'kit' AND (is_active = 1 OR is_active IS NULL)",
      whereArgs: [kitName],
      orderBy: 'id DESC',
    );
    if (catalogRows.isEmpty) {
      // KitBundles and ShutterComponents may differ only by punctuation,
      // accents or a trailing unit such as "mm". Match their normalized
      // catalogue names before deciding that the saved official price is 0.
      final allKitRows = await database.query(
        'ShutterComponents',
        columns: const ['id', 'name', 'price'],
        where:
            "LOWER(TRIM(component_type)) = 'kit' AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'id DESC',
      );
      String normalize(String value) => value
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
          .replaceAll(RegExp(r'\bmm\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final wanted = normalize(kitName);
      catalogRows = allKitRows.where((row) {
        final candidate = normalize('${row['name'] ?? ''}');
        return candidate == wanted ||
            (candidate.isNotEmpty &&
                wanted.isNotEmpty &&
                (candidate.contains(wanted) || wanted.contains(candidate)));
      }).toList();
    }
    if (catalogRows.isEmpty) return null;

    final kitProduct = catalogRows.first;
    final componentId = (kitProduct['id'] as num?)?.toInt();
    final colorId = (widget.model.selectedDbColor?['id'] as num?)?.toInt();
    if (componentId != null && colorId != null) {
      final colorRows = await database.query(
        'ShutterColorPrices',
        columns: const ['price'],
        where: 'shutter_component_id = ? AND color_id = ?',
        whereArgs: [componentId, colorId],
        limit: 1,
      );
      if (colorRows.isNotEmpty) {
        final colorPrice = _safeDouble(colorRows.first['price']);
        if (colorPrice > 0) return colorPrice;
      }
    }
    return _safeDouble(kitProduct['price']);
  }

  Future<Map<String, dynamic>> _withShutterKitPrice(
    Database database,
    Map<String, dynamic> kit,
  ) async {
    final pricedKit = Map<String, dynamic>.from(kit);
    final price = await _readShutterKitPrice(
      database,
      pricedKit['name']?.toString() ?? '',
    );
    if (price != null) {
      pricedKit['price'] = price;
      pricedKit['calculated_price'] = price;
    }
    return pricedKit;
  }

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
    // هذه الكلمات هي نفسها التي تستعملها نافذة «تغيير». لا تعتمد على
    // component_type فقط، لأن الكتالوجات القديمة تستعمل أسماء مثل Bague
    // Filet بدلاً من Embout أو L'axe بدلاً من laxe.
    final normalizedType = componentType.toLowerCase().trim();
    final aliases = <String>[normalizedType];
    if (normalizedType == 'laxe' || normalizedType == 'axe') {
      aliases.addAll(['axe', "l'axe", 'محور']);
    } else if (normalizedType == 'embout') {
      aliases.addAll(['embout', 'bague filet', 'bague fil', 'blague flit']);
    } else if (normalizedType == 'support_roulement') {
      aliases.addAll(['support roulement', 'roulement', 'سيبور رولمو']);
    } else if (normalizedType == 'support_moteur') {
      aliases.addAll(['support moteur', 'سيبور موتور']);
    } else if (normalizedType == 'attache') {
      aliases.addAll(['attache', 'attaches', 'أطاش']);
    }

    final matchClause = aliases
        .map(
          (_) =>
              '(LOWER(component_type) = ? OR LOWER(name) LIKE ? OR LOWER(component_type) LIKE ?)',
        )
        .join(' OR ');
    final matchArgs = <dynamic>[];
    for (final alias in aliases) {
      matchArgs.addAll([alias, '%$alias%', '%$alias%']);
    }
    var queryRes = await dbInstance.query(
      'ShutterComponents',
      where:
          '($matchClause) AND LOWER(shutter_subtype) = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [...matchArgs, subtype.toLowerCase()],
    );
    // An attache is mechanically tied to its blade.  Never fall back from a
    // normal blade to an X3D attache (or the reverse) merely to fill a row.
    if (queryRes.isEmpty &&
        normalizedType != 'attache' &&
        normalizedType != 'bouchon_lame') {
      // خطة بديلة: نفس الدور دون شرط subtype، مع بقاء تصفية الدور نفسها.
      queryRes = await dbInstance.query(
        'ShutterComponents',
        where: '($matchClause) AND (is_active = 1 OR is_active IS NULL)',
        whereArgs: matchArgs,
      );
    }
    if (queryRes.isNotEmpty) {
      final candidates = List<Map<String, dynamic>>.from(queryRes);
      if (normalizedType == 'embout') {
        // Bague Filet هو الافتراضي المطلوب؛ لا نستبدله بباغة الصندوق لمجرد
        // أنها جاءت أولاً في قاعدة البيانات.
        candidates.sort((a, b) {
          int score(Map<String, dynamic> item) {
            final name = (item['name'] ?? '').toString().toLowerCase();
            if (name.contains('bague filet') ||
                name.contains('bague fil') ||
                name.contains('blague flit')) {
              return 0;
            }
            if (name.contains('caisson') || name.contains('صندوق')) return 2;
            return 1;
          }

          return score(a).compareTo(score(b));
        });
      }
      final row = Map<String, dynamic>.from(
        candidates.first,
      ); // نسخة قابلة للتعديل من النتيجة
      final colorPrices = await dbInstance.query(
        'ShutterColorPrices',
        where: 'shutter_component_id = ?',
        whereArgs: [row['id']],
      );
      row['calculated_price'] = resolveShutterComponentUnitPrice(
        component: row,
        colorPrices: colorPrices,
        selectedColorId: (widget.model.selectedDbColor?['id'] as num?)?.toInt(),
      );
      return row;
    }
    return null; // لا يوجد مكوّن مطابق
  }

  Future<Map<String, dynamic>?> _findBladeEndCap(
    Map<String, dynamic> blade,
  ) async {
    final database = await SqlDatabase().db;
    if (database == null) return null;
    final bladeName = (blade['name'] ?? '').toString().trim();
    if (bladeName.isEmpty) return null;
    final rows = await database.query(
      'ShutterComponents',
      where:
          "LOWER(TRIM(component_type)) = 'bouchon_lame' AND LOWER(TRIM(shutter_subtype)) = LOWER(TRIM(?)) AND (is_active = 1 OR is_active IS NULL)",
      whereArgs: [bladeName],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final result = Map<String, dynamic>.from(rows.first);
    result['calculated_price'] = _safeDouble(
      result['price_dzd'] ?? result['price'],
    );
    return result;
  }

  // ==========================================================================
  // دالة: _findClosestFinalBlade
  // الغرض: إيجاد "الشريحة النهائية" (Final Blade) الأقرب حجمًا لمقاس الشريحة
  // العادية المختارة (targetSize)، ضمن نفس الـ subtype، مع خطة بديلة أوسع.
  // ==========================================================================
  bool _isX3dBlade(Map<String, dynamic>? blade) {
    if (blade == null) return false;
    final text = '${blade['name'] ?? ''} ${blade['shutter_subtype'] ?? ''}'
        .toLowerCase();
    return text.contains('x3d') ||
        text.contains('extrud') ||
        text.contains('إكسترودي') ||
        text.contains('اكسترودي');
  }

  /// Finds a shutter axis after applying the same compatibility rules used by
  /// the selector: blade relation first, then motor diameter.  Keeping this
  /// here prevents an automatic replacement from bypassing the dialog rules.
  Future<Map<String, dynamic>?> _findCompatibleShutterAxis({
    Map<String, dynamic>? blade,
    Map<String, dynamic>? motor,
  }) async {
    final dbInstance = await SqlDatabase().db;
    if (dbInstance == null) return null;

    final rows = await dbInstance.query(
      'ShutterComponents',
      where: '(is_active = 1 OR is_active IS NULL)',
    );
    var candidates = rows
        .where((row) {
          final type = (row['component_type'] ?? '').toString().toLowerCase();
          final name = (row['name'] ?? '').toString().toLowerCase();
          return type == 'laxe' ||
              type == 'axe' ||
              type.contains('محور') ||
              name.contains('axe') ||
              name.contains('محور');
        })
        .map(Map<String, dynamic>.from)
        .toList();

    final bladeName = (blade?['name'] ?? '').toString().trim().toLowerCase();
    final bladeIsX3d = _isX3dBlade(blade);
    candidates = candidates.where((axis) {
      final text = '${axis['name'] ?? ''} ${axis['shutter_subtype'] ?? ''}'
          .toLowerCase();
      return bladeIsX3d ? text.contains('x3d') : !text.contains('x3d');
    }).toList();

    if (bladeName.isNotEmpty) {
      final explicitlyLinked = candidates.where((axis) {
        return (axis['shutter_subtype'] ?? '')
                .toString()
                .trim()
                .toLowerCase() ==
            bladeName;
      }).toList();
      if (explicitlyLinked.isNotEmpty) candidates = explicitlyLinked;
    }

    final motorDiameter = motor == null
        ? null
        : shutterComponentDiameter(motor);
    if (motorDiameter != null && motorDiameter > 0) {
      candidates = candidates.where((axis) {
        final axisDiameter = shutterComponentDiameter(axis);
        return axisDiameter != null && axisDiameter >= motorDiameter;
      }).toList();
    }

    candidates.sort((a, b) {
      final aDiameter = shutterComponentDiameter(a) ?? double.infinity;
      final bDiameter = shutterComponentDiameter(b) ?? double.infinity;
      return aDiameter.compareTo(bDiameter);
    });
    if (candidates.isEmpty) return null;

    final axis = Map<String, dynamic>.from(candidates.first);
    axis['calculated_price'] = _safeDouble(axis['price_dzd'] ?? axis['price']);
    return axis;
  }

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
    if (finalBlades.isEmpty)
      return null; // لا توجد شريحة نهائية أصلًا في القاعدة
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
    closest ??= finalBlades
        .first; // إذا كل المقاسات كانت 0 أو غير صالحة، خذ أول نتيجة كخيار أخير
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

  // ------------------ ثوابت أبعاد أعمدة الجدول (بالبكسل) ------------------
  static const double _rowMinHeight =
      56; // ارتفاع أدنى فقط — الصف يتمدّد حسب محتواه
  static const String _colImg = 'image';
  static const String _colName = 'name';
  static const String _colQty = 'quantity';
  static const String _colActualMeters = 'actual_meters';
  static const String _colPrice = 'price';
  static const String _colEstimated = 'estimated';
  static const String _colTotal = 'total';
  static const String _colLen = 'length';
  static const String _colColor = 'color';
  static const String _colCheck = 'check';
  static const double _defaultWImg = 50; // عرض عمود الصورة
  static const double _defaultWName = 220; // عرض عمود اسم المكوّن
  static const double _defaultWColor = 100; // عرض عمود اللون
  static const double _defaultWLen = 100; // عرض عمود الطول
  static const double _defaultWQty = 80; // عرض عمود الكمية
  static const double _defaultWActualMeters = 105; // الأمتار الفعلية المستعملة
  static const double _defaultWPrice = 120; // عرض عمود سعر الوحدة
  static const double _defaultWEstimated = 140; // المطلوب الفعلي × سعر الوحدة
  static const double _defaultWTotal = 140; // سعر الوحدة × المطلوب الحقيقي
  static const double _defaultWCheck = 80; // عرض عمود مربع التفعيل
  static const String _tableColumnLayoutKey =
      'material_consumption_table_columns_v1';
  final Map<String, double> _tableColumnWidths = {};
  Future<SharedPreferences>? _tablePreferencesFuture;
  Future<void> _tablePersistenceQueue = Future<void>.value();
  Timer? _tableColumnSaveDebounce;
  int _tablePreferencesLoadGeneration = 0;

  double _columnWidth(String key, double fallback) =>
      _tableColumnWidths[key] ?? fallback;

  double get _wImg => _columnWidth(_colImg, _defaultWImg);

  double get _wName => _columnWidth(_colName, _defaultWName);

  double get _wColor => _columnWidth(_colColor, _defaultWColor);

  double get _wLen => _columnWidth(_colLen, _defaultWLen);

  double get _wQty => _columnWidth(_colQty, _defaultWQty);

  double get _wActualMeters =>
      _columnWidth(_colActualMeters, _defaultWActualMeters);

  double get _wPrice => _columnWidth(_colPrice, _defaultWPrice);

  double get _wEstimated => _columnWidth(_colEstimated, _defaultWEstimated);

  double get _wTotal => _columnWidth(_colTotal, _defaultWTotal);

  double get _wCheck => _columnWidth(_colCheck, _defaultWCheck);

  double get _minW =>
      _wImg +
      _wName +
      _wColor +
      _wLen +
      _wQty +
      _wActualMeters +
      _wPrice +
      _wEstimated +
      _wTotal +
      _wCheck;

  double get _frozenWidth => _wName;

  double _columnMinWidth(String key) {
    switch (key) {
      case _colImg:
        return 46;
      case _colName:
        return 150;
      case _colQty:
      case _colCheck:
        return 70;
      case _colActualMeters:
        return 95;
      case _colPrice:
      case _colEstimated:
      case _colTotal:
        return 105;
      default:
        return 85;
    }
  }

  double _columnMaxWidth(String key) {
    switch (key) {
      case _colName:
        return 520;
      case _colColor:
        return 260;
      default:
        return 320;
    }
  }

  double _defaultColumnWidth(String key) {
    switch (key) {
      case _colImg:
        return _defaultWImg;
      case _colName:
        return _defaultWName;
      case _colQty:
        return _defaultWQty;
      case _colActualMeters:
        return _defaultWActualMeters;
      case _colPrice:
        return _defaultWPrice;
      case _colEstimated:
        return _defaultWEstimated;
      case _colTotal:
        return _defaultWTotal;
      case _colLen:
        return _defaultWLen;
      case _colColor:
        return _defaultWColor;
      case _colCheck:
        return _defaultWCheck;
      default:
        return 100;
    }
  }

  void _resizeColumn(String key, double delta) {
    final current = _columnWidth(key, _defaultColumnWidth(key));
    _tablePreferencesLoadGeneration++;
    setState(() {
      _tableColumnWidths[key] = (current + delta)
          .clamp(_columnMinWidth(key), _columnMaxWidth(key))
          .toDouble();
    });
    _tableColumnSaveDebounce?.cancel();
    _tableColumnSaveDebounce = Timer(
      const Duration(milliseconds: 250),
      _persistTableColumnLayout,
    );
  }

  void _finishColumnResize() {
    _tableColumnSaveDebounce?.cancel();
    _tableColumnSaveDebounce = null;
    _persistTableColumnLayout();
  }

  Future<SharedPreferences> _getTablePreferences() =>
      _tablePreferencesFuture ??= SharedPreferences.getInstance();

  Future<void> _loadTableColumnLayout() async {
    final loadGeneration = ++_tablePreferencesLoadGeneration;
    try {
      final prefs = await _getTablePreferences();
      final raw = prefs.getString(_tableColumnLayoutKey);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final rawWidths = decoded['widths'];
      if (rawWidths is! Map) return;

      final loaded = <String, double>{};
      for (final entry in rawWidths.entries) {
        final value = entry.value;
        final width = value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '');
        if (width != null && width.isFinite) {
          final key = entry.key.toString();
          loaded[key] = width
              .clamp(_columnMinWidth(key), _columnMaxWidth(key))
              .toDouble();
        }
      }
      if (!mounted || loadGeneration != _tablePreferencesLoadGeneration) {
        return;
      }
      setState(() => _tableColumnWidths.addAll(loaded));
    } catch (error) {
      debugPrint('Material table column layout load failed: $error');
    }
  }

  void _persistTableColumnLayout() {
    final widths = <String, double>{..._tableColumnWidths};
    _tablePersistenceQueue = _tablePersistenceQueue.then((_) async {
      try {
        final prefs = await _getTablePreferences();
        await prefs.setString(
          _tableColumnLayoutKey,
          jsonEncode(<String, dynamic>{'widths': widths}),
        );
      } catch (error) {
        debugPrint('Material table column layout save failed: $error');
      }
    });
  }

  // ==========================================================================
  // دالة: _fetchDefaults  ⭐ (الدالة الأهم في الملف)
  // الغرض: عند فتح الشاشة أو تغيير أي إعداد، تقوم "بالجلب الذكي" لكل المكونات
  // الافتراضية المرتبطة (حديد الدعم، البراغي، الأقفال، الكيتات، المحرك المناسب
  // حسب الوزن...)، وتضبط activeVariants حسب آلية الستار (محرك/مانيفيل/حزام)
  // وحالة الصندوق (تونيل أو لا).
  // ==========================================================================
  void _refreshStrictActiveVariants() {
    final isTunnel = widget.model.isCaissonTunnel;
    final isMotor = widget.model.shutterMechanism == 'محرك';
    activeVariants.addAll(
      ComponentCalculator.standardActiveVariants(widget.model),
    );

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
    }
  }

  Future<void> _loadStrictKitBundles(
    Database dbInstance,
    SqlDatabase sqlDb,
  ) async {
    final kits = await sqlDb.readKitBundles();
    final bundleData = <String, List<Map<String, dynamic>>>{};
    final perLeafMap = <String, bool>{};
    final metadata = <String, Map<String, dynamic>>{};
    final prices = <String, double>{};

    // Kit definitions are independent. Loading them one after another made
    // every kit wait for all of its child/range queries before the table could
    // be shown.
    final loadedKits = await Future.wait(
      kits.map((kit) async {
        final kitName = kit['name']?.toString() ?? '';
        final kitId = (kit['id'] as num?)?.toInt();
        if (kitName.isEmpty || kitId == null) return null;

        final detailsFuture = sqlDb.readKitBundleItemsWithDetails(
          kitId,
          topLevelOnly: true,
        );
        final priceFuture = _isShutterKitBundle(kit)
            ? _readShutterKitPrice(dbInstance, kitName)
            : Future<double?>.value(null);
        final details = await detailsFuture;
        final price = await priceFuture;
        return (
          name: kitName,
          details: details,
          perLeaf: (kit['per_leaf'] ?? 0) == 1,
          metadata: Map<String, dynamic>.from(kit),
          price: price,
        );
      }),
    );
    for (final loaded in loadedKits) {
      if (loaded == null) continue;
      bundleData[loaded.name] = loaded.details
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      perLeafMap[loaded.name] = loaded.perLeaf;
      metadata[loaded.name] = loaded.metadata;
      if (loaded.price != null) prices[loaded.name] = loaded.price!;
    }

    _kitBundleData = bundleData;
    _kitPerLeafMap = perLeafMap;
    _kitBundleMetadata = metadata;
    _kitBundlePrices = prices;
  }

  List<BomItem> _generateRawBomItems() {
    return ComponentCalculator.generateBom(
      widget.model,
      activeVariants,
      kitBundleData: _kitBundleData,
      kitPerLeafMap: _kitPerLeafMap,
      kitBundlePrices: _kitBundlePrices,
      kitBundleMetadata: _kitBundleMetadata,
    );
  }

  /// Safe local fallback while the catalogue database is opening. Catalogue
  /// products are intentionally withheld until their active-series rule has
  /// been verified; only non-catalogue calculated materials may appear here.
  List<BomItem> _resolvedFallbackBomItems(Iterable<BomItem> items) {
    return items
        .where((item) {
          final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
          final qty = item.requiredQuantity > 0
              ? item.requiredQuantity
              : item.quantity;
          if (!item.isActive || (!hasPieces && qty <= 0)) return false;
          final category = item.selectorCategory ?? item.category;
          final requiresCatalogueIdentity = const {
            'profile',
            'accessory',
            'other',
            'joint',
          }.contains(category);
          return !requiresCatalogueIdentity;
        })
        .toList(growable: false);
  }

  Future<List<BomItem>> _applyPurchasePricesIfEnabled(
    List<BomItem> items,
  ) async {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (!settings.applyPurchasePricesToCostTable) return items;

    final sqlDb = SqlDatabase();
    final updatedList = <BomItem>[];

    for (final item in items) {
      final itemId = item.catalogItemId;
      if (itemId == null || itemId <= 0) {
        updatedList.add(item);
        continue;
      }

      String itemType;
      if (item.category == 'profile') {
        itemType = 'Sections';
      } else if (item.category == 'accessory') {
        itemType = 'Accessories';
      } else if (item.category == 'shutter') {
        itemType = 'ShutterComponents';
      } else if (item.category == 'joint') {
        itemType = 'Joints';
      } else if (item.category == 'glass') {
        itemType = 'Glass';
      } else {
        itemType = item.inventoryItemType ?? 'Accessories';
      }

      final rawColorId = item.category == 'accessory'
          ? _selectedAccessoryColorId()
          : (item.colorId ?? widget.model.selectedDbColor?['id']);
      final colorId = rawColorId is num
          ? rawColorId.toInt()
          : int.tryParse('${rawColorId ?? ''}');

      final purchasePrice = await sqlDb.getLatestPurchasePrice(
        itemId: itemId,
        itemType: itemType,
        colorId: colorId,
      );

      if (purchasePrice != null && purchasePrice > 0) {
        updatedList.add(item.copyWith(unitPrice: purchasePrice));
      } else {
        updatedList.add(item);
      }
    }
    return updatedList;
  }

  Future<List<BomItem>> _generateStrictVisibleBomItems(
    BomEngineV2 engine,
  ) async {
    final rawItems = _generateRawBomItems();
    final items = await engine.filterItemsByAvailableCandidates(
      window: widget.model,
      items: rawItems,
    );
    return items
        .where((item) {
          final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
          final qty = item.requiredQuantity > 0
              ? item.requiredQuantity
              : item.quantity;
          return hasPieces || qty > 0;
        })
        .toList(growable: false);
  }

  Future<void> _refreshVisibleBomItems() async {
    if (_isRefreshingVisibleBom || _isFetchingDefaults) return;
    _isRefreshingVisibleBom = true;
    try {
      final refreshGeneration = ++_bomRefreshGeneration;
      final engine = BomEngineV2(database: SqlDatabase());
      // Revalidate saved selections whenever the window/series changes. Without
      // this pass, a selection resolved for the previous series could remain
      // visible until the screen was recreated.
      final rawBomItems = _generateRawBomItems();
      var visibleBomItems = _resolvedFallbackBomItems(rawBomItems);
      try {
        await engine.stabilizeSelections(
          window: widget.model,
          items: rawBomItems,
        );
        final dbReady = await SqlDatabase().db != null;
        if (dbReady) {
          final strictItems = await _generateStrictVisibleBomItems(engine);
          if (strictItems.isNotEmpty || visibleBomItems.isEmpty) {
            visibleBomItems = strictItems;
          }
        }
        visibleBomItems = await _applyPurchasePricesIfEnabled(visibleBomItems);
      } catch (error, stackTrace) {
        // Keep resolved rows visible without restoring unlinked placeholders.
        visibleBomItems = _resolvedFallbackBomItems(_generateRawBomItems());
        visibleBomItems = await _applyPurchasePricesIfEnabled(visibleBomItems);
        debugPrint(
          'Material BOM refresh failed; showing resolved rows: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      final refreshedStock = await _loadMainWarehouseStock();
      if (!mounted || refreshGeneration != _bomRefreshGeneration) return;
      final stockChanged =
          refreshedStock.length != _mainWarehouseStock.length ||
          refreshedStock.entries.any(
            (e) => _mainWarehouseStock[e.key] != e.value,
          );
      if (stockChanged ||
          _bomItemsSignature(_visibleBomItems) !=
              _bomItemsSignature(visibleBomItems)) {
        setState(() {
          _mainWarehouseStock = refreshedStock;
          _visibleBomItems = visibleBomItems;
        });
      }
    } finally {
      _isRefreshingVisibleBom = false;
    }
  }

  void _updateRequestedQuantity(int quantity) {
    if (quantity <= 0 || quantity == widget.model.quantity) return;

    // Rebuild immediately so the quantity/cost rows and totals react in the
    // same frame as the Parameters field. The async refresh below then
    // reapplies strict catalogue selections, purchase prices and stock data.
    widget.model.quantity = quantity;
    final immediateItems = _resolvedFallbackBomItems(_generateRawBomItems());
    setState(() {
      _visibleBomItems = immediateItems;
    });

    _scheduleQuantityRefresh();
  }

  void _scheduleQuantityRefresh() {
    _modelRefreshDebounce?.cancel();
    _modelRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (_isRefreshingVisibleBom || _isFetchingDefaults) {
        _scheduleQuantityRefresh();
        return;
      }
      unawaited(_refreshVisibleBomItems());
    });
  }

  String _bomItemsSignature(Iterable<BomItem> items) => items
      .map(
        (item) => [
          item.catalogItemId,
          item.originalName,
          item.name,
          item.category,
          item.colorId,
          item.quantity,
          item.unitPrice,
          item.isActive,
        ].join('|'),
      )
      .join('||');

  bool _hasRepeatedForRestoredSeries = false;

  void _setFetchProgress(double value) {
    if (!mounted || !_isFetchingDefaults) return;
    setState(() => _fetchProgress = value.clamp(0.0, 1.0).toDouble());
  }

  Future<void> _fetchDefaults() async {
    if (_isFetchingDefaults) return;
    // Catalogue restoration runs asynchronously when an order is reopened.
    // Remember its current series so a fetch that started before restoration
    // can transparently repeat once the real drawing series is available.
    final seriesIdAtFetchStart =
        widget.model.activeFrameSeries?.id ??
        widget.model.effectiveSlidingSeries?.id ??
        widget.model.activeSeries?.id;
    if (mounted) {
      setState(() {
        _isFetchingDefaults = true;
        _fetchProgress = 0.20;
      });
    }
    _accessoryPriceCache.clear();
    // Never publish the preliminary/raw BOM. The table is published only
    // after defaults, catalogue links and the strict visibility check finish.
    var visibleBomItems = const <BomItem>[];
    var mustRepeatForRestoredSeries = false;
    try {
      final sqlDb = SqlDatabase();

      // Run prerequisites sequentially with timeouts to avoid database lock contention.
      try {
        await widget.model.loadGlassProducts().timeout(
          const Duration(seconds: 4),
        );
      } catch (e) {
        debugPrint('loadGlassProducts error/timeout: $e');
      }
      _setFetchProgress(0.30);

      try {
        await widget.model.updateShutterDefaultsIfNeeded().timeout(
          const Duration(seconds: 4),
        );
      } catch (e) {
        debugPrint('updateShutterDefaultsIfNeeded error/timeout: $e');
      }
      _setFetchProgress(0.40);

      try {
        await _loadPricesFromDb().timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('_loadPricesFromDb error/timeout: $e');
      }
      _setFetchProgress(0.50);

      _refreshStrictActiveVariants();
      if (!widget.model.hasSimpleGlassForReducer ||
          widget.model.hasDoubleGlassForRules) {
        widget.model.clearReducerOverride();
      }

      final dbInstance = await sqlDb.db;
      if (dbInstance != null) {
        try {
          await _loadStrictKitBundles(
            dbInstance,
            sqlDb,
          ).timeout(const Duration(seconds: 4));
        } catch (e) {
          debugPrint('_loadStrictKitBundles error/timeout: $e');
        }
        _setFetchProgress(0.65);

        try {
          final stock = await _loadMainWarehouseStock().timeout(
            const Duration(seconds: 4),
          );
          if (mounted) setState(() => _mainWarehouseStock = stock);
        } catch (e) {
          debugPrint('_loadMainWarehouseStock error/timeout: $e');
        }
      }
      _setFetchProgress(0.75);

      final engine = BomEngineV2(database: sqlDb);
      var bomItems = _generateRawBomItems();
      try {
        await engine
            .stabilizeSelections(window: widget.model, items: bomItems)
            .timeout(const Duration(seconds: 4));
        // Stabilization can select catalogue components. Rebuild and run one
        // more pass so quick "Ajouter" and the manually opened quantity table
        // price the exact same final BOM rather than two successive states.
        bomItems = _generateRawBomItems();
        await engine
            .stabilizeSelections(window: widget.model, items: bomItems)
            .timeout(const Duration(seconds: 4));
        bomItems = _generateRawBomItems();
      } catch (e) {
        debugPrint('stabilizeSelections error/timeout: $e');
      }

      if (dbInstance == null) {
        visibleBomItems = _resolvedFallbackBomItems(bomItems);
      } else {
        try {
          final strictItems = await _generateStrictVisibleBomItems(
            engine,
          ).timeout(const Duration(seconds: 5));
          final resolvedItems = _resolvedFallbackBomItems(bomItems);
          visibleBomItems = strictItems.isEmpty && resolvedItems.isNotEmpty
              ? resolvedItems
              : strictItems;
        } catch (e) {
          debugPrint('_generateStrictVisibleBomItems error/timeout: $e');
          visibleBomItems = _resolvedFallbackBomItems(bomItems);
        }
      }
      try {
        visibleBomItems = await _applyPurchasePricesIfEnabled(
          visibleBomItems,
        ).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('_applyPurchasePricesIfEnabled error/timeout: $e');
      }
      _setFetchProgress(0.95);
    } catch (error, stackTrace) {
      // A later pricing failure must not erase additive rule rows (Clam,
      // assembly screws, kits) already calculated successfully above.
      if (visibleBomItems.isEmpty) {
        visibleBomItems = _resolvedFallbackBomItems(_generateRawBomItems());
      }
      debugPrint(
        'Material defaults load failed; showing resolved rows: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _visibleBomItems = visibleBomItems;
          _fetchProgress = 1.0;
          _isFetchingDefaults = false;
          _hasFetchedDefaults = true;
        });
      }
      final seriesIdAfterFetch =
          widget.model.activeFrameSeries?.id ??
          widget.model.effectiveSlidingSeries?.id ??
          widget.model.activeSeries?.id;
      if (seriesIdAfterFetch != null &&
          seriesIdAfterFetch != seriesIdAtFetchStart &&
          !_hasRepeatedForRestoredSeries) {
        _hasRepeatedForRestoredSeries = true;
        mustRepeatForRestoredSeries = true;
        unawaited(_fetchDefaults());
      }
      if (_pricePerLinearMeterFromDb == 0 ||
          (widget.model.hasShutter && _shutterSqmPriceFromDb == 0) ||
          (widget.model.hasMoustiquaireAddon &&
              _moustiquaireSqmPriceFromDb <= 0)) {
        _scheduleInitialPriceRetries();
      }
    }
    if (widget.autoCalculateAndSave &&
        !mustRepeatForRestoredSeries &&
        !_automaticCompletionStarted &&
        mounted) {
      // The manual table remains open long enough for its price retry to
      // finish. The quick Ajouter path must not save an earlier zero/default
      // tariff, otherwise both buttons calculate the same BOM differently.
      if (_pricePerLinearMeterFromDb == 0 ||
          (widget.model.hasShutter && _shutterSqmPriceFromDb == 0) ||
          (widget.model.hasMoustiquaireAddon &&
              _moustiquaireSqmPriceFromDb <= 0)) {
        try {
          await _loadPricesFromDb().timeout(const Duration(seconds: 8));
        } catch (e) {
          debugPrint('Final automatic price load error/timeout: $e');
        }
      }
      _automaticCompletionStarted = true;
      final pricedItems = _visibleBomItems
          .where((item) {
            final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
            final qty = item.requiredQuantity > 0
                ? item.requiredQuantity
                : item.quantity;
            return hasPieces || qty > 0;
          })
          .toList(growable: false);
      final totals = _calculateTotals(pricedItems);
      final sellingPrice = totals['total']?['selling'] ?? 0.0;
      final quantity = math.max(1, widget.model.quantity);
      final unitPrice = sellingPrice / quantity;
      if (unitPrice.isFinite && unitPrice > 0) {
        widget.model.totalCost = unitPrice;
        widget.model.manualPriceOverride = unitPrice;
        Navigator.pop(context, true);
      } else {
        _automaticCompletionStarted = false;
        Navigator.pop(context, false);
      }
    }
  }

  String _priceContextSignature() {
    final model = widget.model;
    final color = model.selectedDbColor?['id']?.toString() ?? '';
    final series =
        model.activeFrameSeries?.id ??
        model.effectiveSlidingSeries?.id ??
        model.activeSeries?.id;
    final bladeOverride = model.componentOverrides['الشرائح (Lames)'];
    final bladeName = bladeOverride?['name']?.toString() ?? model.shutterLame;
    final bladeSubtype = bladeOverride?['shutter_subtype']?.toString() ?? '';
    return '$series|$color|${model.hasShutter}|$bladeName|$bladeSubtype';
  }

  void _scheduleInitialPriceRetries() {
    if (_initialPriceRetryTimers.isNotEmpty) return;
    for (final delay in const [
      Duration(milliseconds: 350),
      Duration(seconds: 1),
      Duration(seconds: 3),
    ]) {
      _initialPriceRetryTimers.add(
        Timer(delay, () {
          if (!mounted) return;
          if (_isFetchingDefaults) return;
          unawaited(_loadPricesFromDb());
        }),
      );
    }
  }

  Widget _buildFetchProgress(AppLanguage lang) {
    final progress = _fetchProgress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  value: progress < 1 ? null : 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Localization.translate(
                    'جاري تجهيز الكميات والأسعار...',
                    lang,
                  ),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
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
    // Cost settings and database prices must not load concurrently. The
    // settings loader initializes the linear-price field to zero, so if it
    // finishes after the database query it can overwrite the valid price.
    activeVariants = ComponentCalculator.standardActiveVariants(widget.model);
    // لا تعرض نسخة BOM أولية؛ انشر فقط النتيجة بعد اكتمال الفحص الصارم.
    _visibleBomItems = const <BomItem>[];
    _hasFetchedDefaults = false;
    final initialColorId = widget.model.selectedDbColor?['id'];
    _lastBomColorId = initialColorId is num
        ? initialColorId.toInt()
        : int.tryParse('${initialColorId ?? ''}');
    unawaited(_loadTableColumnLayout());
    // Load local settings first, then resolve the BOM and database prices.
    // This makes the saved linear-metre price visible on the first opening,
    // without requiring the refresh button.
    unawaited(
      _loadCostSettings().then((_) {
        if (mounted) return _fetchDefaults();
      }),
    );
    _scheduleInitialPriceRetries();
    // الاستماع لأي تغيير في النموذج (مثلاً تغيير القياسات من شاشة أخرى) لإعادة رسم الواجهة
    widget.model.addListener(_onModelChanged);
    _dbUpdateSubscription = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        unawaited(_refreshFromDatabaseUpdate());
      }
    });
  }

  Future<void> _refreshFromDatabaseUpdate() async {
    final newStock = await _loadMainWarehouseStock();
    if (mounted) {
      setState(() => _mainWarehouseStock = newStock);
      await _refreshVisibleBomItems();
    }
  }

  // دالة تُستدعى عند تغيّر النموذج من خارج هذه الشاشة، فقط تعيد بناء الواجهة
  void _onModelChanged() {
    if (_isFetchingDefaults || _isRefreshingVisibleBom) return;
    final priceContext = _priceContextSignature();
    if (priceContext != _lastPriceContextSignature) {
      _lastPriceContextSignature = priceContext;
      // Model restoration may assign the actual BS90/shutter data after this
      // screen has already started its first query. Reload just the dynamic
      // prices for that new context immediately.
      unawaited(_loadPricesFromDb());
    }
    final rawColorId = widget.model.selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse('${rawColorId ?? ''}');
    final colorChanged = colorId != _lastBomColorId;
    _lastBomColorId = colorId;
    // Catalogue stabilization mutates resolved selections and notifies the
    // model. Ignore those internal notifications; treating them as a fresh
    // user edit created a self-sustaining refresh loop.
    if (_isFetchingDefaults || _isRefreshingVisibleBom) return;
    _modelRefreshDebounce?.cancel();
    if (colorChanged && _hasFetchedDefaults && !_isFetchingDefaults) {
      // A colour changes section prices, shutter colour prices and accessory
      // prices; refreshing only the existing rows leaves stale/empty totals.
      unawaited(_fetchDefaults());
      return;
    }
    if (_hasFetchedDefaults) {
      _modelRefreshDebounce = Timer(const Duration(milliseconds: 180), () {
        if (mounted) unawaited(_refreshVisibleBomItems());
      });
    }
  }

  // ==========================================================================
  // dispose: تنظيف الموارد عند إغلاق الشاشة (إلغاء الاستماع، تحرير الكونترولرز)
  // ==========================================================================
  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    _dbUpdateSubscription?.cancel();
    _modelRefreshDebounce?.cancel();
    for (final timer in _initialPriceRetryTimers) {
      timer.cancel();
    }
    _initialPriceRetryTimers.clear();
    _tableColumnSaveDebounce?.cancel();
    if (_tableColumnWidths.isNotEmpty) {
      _persistTableColumnLayout();
    }
    _scrollController.dispose();
    _pageScrollController.dispose();
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
      _profitMargin =
          prefs.getDouble('app_profit_margin') ?? 0.0; // افتراضي 20%
      _pricePerSqm =
          prefs.getDouble('app_price_per_sqm') ?? 0.0; // افتراضي 00 دج/م²
      _torqueFactor =
          prefs.getDouble('shutter_torque_factor') ?? 1.5; // افتراضي 1.5
      // ملاحظة: سعر المتر الخطي يُحمَّل دائمًا من قاعدة البيانات وليس من SharedPreferences
      final methodIndex =
          prefs.getInt('app_cost_method') ?? CostMethod.percentage.index;
      _costMethod =
          CostMethod.values[methodIndex]; // تحويل الرقم المحفوظ إلى enum
      if (_isShutterOnlyPricing && _costMethod == CostMethod.linearMeter) {
        _costMethod = CostMethod.percentage;
      }
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
    final generation = ++_priceLoadGeneration;
    final dbInstance = await SqlDatabase().db;
    if (dbInstance == null) return;
    final profileRules = <int, Map<String, dynamic>>{};
    try {
      final profileRuleRows = await SqlDatabase().getProfileCalculationRules();
      for (final row in profileRuleRows) {
        final sectionId = (row['section_id'] as num?)?.toInt();
        if (sectionId != null) profileRules[sectionId] = row;
      }
    } catch (e) {
      debugPrint(
        'Error getting profile calculation rules in _loadPricesFromDb: $e',
      );
    }
    final previousLinearMeterPrice = _pricePerLinearMeterFromDb;
    final previousShutterSqmPrice = _shutterSqmPriceFromDb;
    double linearMeterPrice = 0.0;
    double shutterSqmPrice = 0.0;
    double moteurInstall = 0.0;
    double obInstall = 0.0;
    double demiObInstall = 0.0;
    double verrouInstall = 0.0;
    final rawColorId = widget.model.selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse('${rawColorId ?? ''}');
    final seriesId =
        widget.model.activeFrameSeries?.id ??
        widget.model.effectiveSlidingSeries?.id ??
        widget.model.activeSeries?.id;
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
      if (linearMeterPrice == 0.0) {
        // Fallback: search SeriesColorPrices for ANY color price for this series.
        // This prevents a temporary/unknown colour id from wiping a valid
        // linear-metre price that is already configured for the series.
        final anyColorRes = await dbInstance.query(
          'SeriesColorPrices',
          where: 'series_id = ? AND price > 0',
          whereArgs: [seriesId],
          limit: 1,
        );
        if (anyColorRes.isNotEmpty) {
          linearMeterPrice =
              (anyColorRes.first['price'] as num?)?.toDouble() ?? 0.0;
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
      final allSqmPrices = await dbInstance.query('ShutterSqmPrices');
      shutterSqmPrice = WindowModel.resolveShutterSqmPrice(
        bladeName: actualBladeName,
        bladeSubtype: subtype,
        colorId: colorId,
        prices: allSqmPrices,
      );
      // Prefer the exact blade + selected-colour row over fuzzy matching.
      // Fuzzy matching could pick a generic 730 DZD row when the catalogue
      // contains the explicitly configured 8500 DZD price.
      if (colorId != null) {
        final exactColorRows = await dbInstance.query(
          'ShutterSqmPrices',
          columns: ['price_per_sqm'],
          where:
              'LOWER(TRIM(blade_type)) = ? AND color_id = ? AND price_per_sqm > 0',
          whereArgs: [actualBladeName.trim().toLowerCase(), colorId],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (exactColorRows.isNotEmpty) {
          final exactPrice = _safeDouble(exactColorRows.first['price_per_sqm']);
          if (exactPrice > 0) shutterSqmPrice = exactPrice;
        }
      }
      if (shutterSqmPrice == 0.0) {
        final exactRows = await dbInstance.query(
          'ShutterSqmPrices',
          columns: ['price_per_sqm'],
          where: 'LOWER(TRIM(blade_type)) = ? AND price_per_sqm > 0',
          whereArgs: [actualBladeName.trim().toLowerCase()],
          limit: 1,
        );
        if (exactRows.isNotEmpty) {
          shutterSqmPrice = _safeDouble(exactRows.first['price_per_sqm']);
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
    final moustiquaireRes = await dbInstance.query(
      'ShutterSqmPrices',
      columns: ['price_per_sqm'],
      where: 'blade_type = ? AND color_id = ?',
      whereArgs: ['Moustiquaire_Sqm', 0],
      limit: 1,
    );
    final moustiquaireSqmPrice = moustiquaireRes.isEmpty
        ? 0.0
        : _safeDouble(moustiquaireRes.first['price_per_sqm']);
    if (!mounted || generation != _priceLoadGeneration) return;
    final effectiveLinearMeterPrice = linearMeterPrice > 0 || seriesId != null
        ? linearMeterPrice
        : previousLinearMeterPrice;
    final effectiveShutterSqmPrice =
        shutterSqmPrice > 0 || actualBladeName.trim().isNotEmpty
        ? shutterSqmPrice
        : previousShutterSqmPrice;
    // تحديث الحالة (State) بكل الأسعار المحمّلة، وتحديث نصوص الحقول إذا لم يكن هناك تعديل يدوي (override)
    setState(() {
      _profileCalculationRules = profileRules;
      _pricePerLinearMeterFromDb = effectiveLinearMeterPrice;
      _shutterSqmPriceFromDb =
          effectiveShutterSqmPrice; // ⭐️ التحديث الحاسم لسعر الستار
      _moustiquaireSqmPriceFromDb = moustiquaireSqmPrice;
      _moteurInstallFee = moteurInstall;
      _obInstallFee = obInstall;
      _demiObInstallFee = demiObInstall;
      _verrouInstallFee = verrouInstall;
      if (_pricePerLinearMeterOverride == null) {
        _pricePerLinearMeterController.text = effectiveLinearMeterPrice
            .toStringAsFixed(0);
      }
      if (_shutterSqmPriceOverride == null) {
        _shutterSqmPriceController.text = effectiveShutterSqmPrice
            .toStringAsFixed(0);
      }
    });
  }

  // ==========================================================================
  // دالة: _handleKitSelection
  // تُستدعى عند اختيار المستخدم كيتًا مختلفًا يدويًا من القائمة المنسدلة.
  // تحدد نوع الآلية (محرك/مانيفيل/حزام) من اسم الكيت المختار، وتحدّث النموذج
  // والـ overrides بما يتوافق مع الكيت الجديد.
  // ==========================================================================
  Future<void> _handleKitSelection(Map<String, dynamic> selectedKit) async {
    final mutableSelected = Map<String, dynamic>.from(selectedKit);
    mutableSelected['catalog_source'] = 'KitBundles';
    final calculatedPrice = _safeDouble(mutableSelected['calculated_price']);
    final listedPrice = _safeDouble(mutableSelected['price']);
    final databasePrice = _safeDouble(mutableSelected['price_dzd']);
    mutableSelected['calculated_price'] = calculatedPrice > 0
        ? calculatedPrice
        : (listedPrice > 0 ? listedPrice : databasePrice);
    final selectedName = (mutableSelected['name'] ?? '')
        .toString()
        .toLowerCase();
    final selectedCode = normalizeKitDescriptionCode(
      mutableSelected['description'],
    );
    // Check if it is a sliding system kit
    final bool isSliding = widget.model.systemMode == 'sliding';
    if (isSliding) {
      String targetKey = 'كيت 67000 (Kit 67000)';
      if (selectedName.contains('40000')) {
        targetKey = 'كيت 40000 (Kit 40000)';
      } else if (selectedName.contains('67000')) {
        targetKey = 'كيت 67000 (Kit 67000)';
      } else {
        final String sName =
            widget.model.activeSlidingSeries?.name.toLowerCase() ?? '';
        if (sName.contains('40000')) {
          targetKey = 'كيت 40000 (Kit 40000)';
        } else {
          targetKey = 'كيت 67000 (Kit 67000)';
        }
      }
      final slidingKeys = ['كيت 67000 (Kit 67000)', 'كيت 40000 (Kit 40000)'];
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
    String
    targetKitKey; // المفتاح الصحيح لحفظ هذا الكيت تحته في componentOverrides
    // استنتاج نوع الآلية من اسم الكيت (محرك/مانيفيل مع فولي أو بدون/حزام)
    if (selectedCode == 'MT') {
      newMech = 'محرك';
      targetKitKey = 'كيت فولي موتور (Kit Volet Moteur)';
    } else if (selectedCode == 'V') {
      final isCurrentCrank =
          widget.model.shutterMechanism == 'منايفال' ||
          widget.model.shutterMechanism == 'مانيفال' ||
          widget.model.shutterMechanism == 'مانيفر';
      newMech = isCurrentCrank ? 'مانيفال' : 'حزام';
      targetKitKey = isCurrentCrank
          ? 'كيت فولي مانيفر (Kit Volet Manivelle)'
          : 'كيت فولي (Kit Volet)';
    } else {
      // Legacy records without a description code keep their old name-based
      // behaviour. Coded records never rely on commercial names.
      if (selectedName.contains('moteur') || selectedName.contains('محرك')) {
        newMech = 'محرك';
        targetKitKey = 'كيت فولي موتور (Kit Volet Moteur)';
      } else if (selectedName.contains('manivelle') ||
          selectedName.contains('مانيفال') ||
          selectedName.contains('مانيفر')) {
        newMech = 'مانيفال';
        targetKitKey =
            selectedName.contains('volet') || selectedName.contains('فولي')
            ? 'كيت فولي مانيفر (Kit Volet Manivelle)'
            : 'كيت مانيفر (Kit Manivelle)';
      } else {
        newMech = 'حزام';
        targetKitKey =
            selectedName.contains('sangle') || selectedName.contains('حزام')
            ? 'كيت حزام (Kit Sangle)'
            : 'كيت فولي (Kit Volet)';
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
    final selectedKitSize = kitBundleSizeMm(mutableSelected);
    if (selectedKitSize != null && selectedKitSize > 0) {
      final dbInstance = await SqlDatabase().db;
      if (dbInstance != null) {
        final boxes = await dbInstance.query(
          'ShutterComponents',
          where:
              "(LOWER(name) LIKE '%box%' OR name LIKE '%صندوق%' OR LOWER(name) LIKE '%caisson%' OR LOWER(component_type) IN ('box', 'caisson')) AND (is_active = 1 OR is_active IS NULL)",
        );
        for (final row in boxes) {
          final boxSize = double.tryParse(getComponentSize(row) ?? '');
          if (boxSize != null && (boxSize - selectedKitSize).abs() <= 0.5) {
            final companionBox = Map<String, dynamic>.from(row);
            companionBox['calculated_price'] = _safeDouble(
              companionBox['price_dzd'] ?? companionBox['price'],
            );
            companionBox['manual_override'] = true;
            widget.model.componentOverrides['الصندوق (Caisson)'] = companionBox;
            widget.model.setManualShutterBoxHeight(selectedKitSize);
            break;
          }
        }
      }
    }
    // إعادة حساب الافتراضيات (لأن تغيير الآلية يؤثر على مكونات أخرى كثيرة) وتحديث الواجهة
    await widget.model.updateShutterDefaultsIfNeeded();
    await _fetchDefaults();
    if (mounted) {
      setState(() {
        widget.model.refreshUI();
      });
    }
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
      if (name == 'أغطية الشفرات (Bouchons Lames)') {
        const capKey = 'أغطية الشفرات (Bouchons Lames)';
        if (value) {
          final savedCap = _disabledBladeEndCap;
          if (savedCap != null) {
            widget.model.componentOverrides[capKey] = Map<String, dynamic>.from(
              savedCap,
            );
            _disabledBladeEndCap = null;
          }
        } else {
          final currentCap = widget.model.componentOverrides[capKey];
          if (currentCap is Map) {
            _disabledBladeEndCap = Map<String, dynamic>.from(currentCap);
          }
          widget.model.componentOverrides.remove(capKey);
        }
        // Do not let the generic exclusion logic below alter this explicit
        // toggle.  The BOM refresh will recalculate blade lengths from the
        // updated override state.
        widget.model.refreshUI();
        return;
      }
      // تحقق: هل الاسم هو أحد مفاتيح الكيتات؟
      final isAnyKitKey =
          name == 'كيت (Kit)' ||
          name == 'كيت فولي موتور (Kit Volet Moteur)' ||
          name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
          name == 'كيت مانيفر (Kit Manivelle)' ||
          name == 'كيت حزام (Kit Sangle)' ||
          name == 'كيت فولي (Kit Volet)';
      if (name == 'Verrou Central') {
        if (value && !widget.model.canUseOpeningOnlyOptions) {
          activeVariants[name] = false;
          return;
        }
        widget.model.toggleVerrouCentral(
          value,
        ); // تفويض المنطق لدالة النموذج نفسه
      } else if (name == 'System OB') {
        if (value && !widget.model.canUseOpeningOnlyOptions) {
          activeVariants[name] = false;
          return;
        }
        widget.model.toggleSystemOB(value);
      } else if (name == 'Demi System OB') {
        if (!widget.model.canUseDemiOB) {
          activeVariants[name] = false;
          return;
        }
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
      }
      // مزامنة نهائية: إعادة قراءة الحالة الفعلية من النموذج (احتياطًا لأي تعارض)
      activeVariants['Verrou Central'] =
          widget.model.canUseOpeningOnlyOptions &&
          widget.model.useVerrouCentral;
      activeVariants['System OB'] = widget.model.effectiveUseSystemOB;
      activeVariants['Demi System OB'] = widget.model.effectiveUseDemiOB;
      _rememberVariantChoices();
    });
    unawaited(_refreshVisibleBomItems());
  }

  /// Stores the switches that differ from the rules on the drawing, so the
  /// cutting sheet, required goods and a reopened table use the same parts.
  void _rememberVariantChoices() {
    final rules = ComponentCalculator.standardActiveVariants(
      widget.model,
      includeUserChoices: false,
    );
    widget.model.shutterVariantChoices = {
      for (final entry in activeVariants.entries)
        if (!ComponentCalculator.modelBackedVariantKeys.contains(entry.key) &&
            rules.containsKey(entry.key) &&
            rules[entry.key] != entry.value)
          entry.key: entry.value,
    };
    widget.model.shutterVariantChoicesContext =
        ComponentCalculator.shutterVariantContext(widget.model);
  }

  // ==========================================================================
  // build: الدالة الرئيسية لبناء واجهة الشاشة كاملة
  // ==========================================================================
  /// A profile kept from another series (for example BS 90 in a PVC
  /// drawing) makes every quantity and cost below unreliable.
  Widget _buildForeignSeriesWarning(AppLanguage lang, int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${Localization.translate('يحتوي الرسم على مقاطع من سلسلة أخرى؛ الكميات والتكلفة غير موثوقة', lang)} ($count)',
              style: TextStyle(
                color: Colors.red.shade900,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: Text(
              Localization.translate('إزالة المقاطع غير المتوافقة', lang),
            ),
            onPressed: () async {
              widget.model.removeOverridesFromForeignSeries();
              await _fetchDefaults();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (widget.autoCalculateAndSave) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                Localization.translate('جاري تجهيز الكميات والأسعار...', lang),
              ),
            ],
          ),
        ),
      );
    }
    final items = _visibleBomItems
        .where((item) {
          final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
          final qty = item.requiredQuantity > 0
              ? item.requiredQuantity
              : item.quantity;
          return hasPieces || qty > 0;
        })
        .toList(growable: false);
    final foreignSeriesOverrides = widget.model.overridesFromForeignSeries;
    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('الالكمية والتكلفة', lang)),
      ), // شريط العنوان العلوي
      body: SingleChildScrollView(
        controller: _pageScrollController,
        primary: false,
        scrollDirection: Axis.vertical, // تمرير رأسي لكامل محتوى الشاشة
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _handleTablePageWheel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Keep refreshes invisible once a valid table is already shown.
              // The progress panel is only useful for the initial empty load.
              if (_isFetchingDefaults && _visibleBomItems.isEmpty)
                _buildFetchProgress(lang),
              if (foreignSeriesOverrides.isNotEmpty)
                _buildForeignSeriesWarning(lang, foreignSeriesOverrides.length),
              // تحذير ارتفاع الستار (إن وُجد) — يظهر فقط إذا كان هناك تحذير في النموذج
              if (widget.model.shutterHeightWarning != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                          widget.model.shutterHeightWarning!,
                          // نص التحذير القادم من النموذج
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
              // Manual blade selections remain visible in the BOM, but a blade
              // whose database width limit is too small must be clearly flagged.
              if (widget.model.shutterWidthWarning != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.straighten,
                        color: Colors.orange.shade800,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.model.localizedShutterWidthWarning(lang) ??
                              widget.model.shutterWidthWarning!,
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.model.recommendedShutterBlade != null) ...[
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: Text(
                            lang == AppLanguage.french
                                ? 'Appliquer la lame recommandée'
                                : (lang == AppLanguage.english
                                      ? 'Apply recommended blade'
                                      : 'تطبيق الشفرة المقترحة'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            widget.model.applyRecommendedShutterBlade();
                            await widget.model.updateShutterDefaultsIfNeeded();
                            await _fetchDefaults();
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
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
                        painter: WindowPainter(
                          model: widget.model,
                          repaintToken: _bomRefreshGeneration,
                        ), // الرسام المخصص
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
                final lang = Provider.of<AppSettingsProvider>(
                  context,
                  listen: false,
                ).language;
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
                        ? (isDark
                              ? Colors.green.shade900.withValues(alpha: 0.3)
                              : Colors.green.shade50)
                        : (hasLightKit
                              ? (isDark
                                    ? Colors.blue.shade900.withValues(
                                        alpha: 0.3,
                                      )
                                    : Colors.blue.shade50)
                              : (isDark
                                    ? Colors.blueGrey.shade900.withValues(
                                        alpha: 0.3,
                                      )
                                    : Colors.blueGrey.shade50)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isLightKitActive
                          ? (isDark
                                ? Colors.green.shade700
                                : Colors.green.shade200)
                          : (hasLightKit
                                ? (isDark
                                      ? Colors.blue.shade700
                                      : Colors.blue.shade200)
                                : (isDark
                                      ? Colors.blueGrey.shade700
                                      : Colors.blueGrey.shade200)),
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
                            color: isDark
                                ? Colors.white60
                                : Colors.blueGrey.shade500,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.blueGrey.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      '${Localization.translate('العرض:', lang)} ',
                                ),
                                TextSpan(
                                  text:
                                      '${widget.model.width.toStringAsFixed(0)} mm',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A237E),
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
                                TextSpan(
                                  text:
                                      '${Localization.translate('الارتفاع:', lang)} ',
                                ),
                                TextSpan(
                                  text:
                                      '${widget.model.height.toStringAsFixed(0)} mm',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A237E),
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
                                  ? Icons
                                        .check_circle // أخضر = مفعّل فعليًا
                                  : Icons
                                        .info_outline, // أزرق = متاح لكن غير مفعّل
                              color: isLightKitActive
                                  ? Colors.green
                                  : Colors.blue,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      if (widget.model.systemMode == 'sliding')
                        (() {
                          final hasSlidingSash = widget.model.zones.any(
                            (z) => z.content == ZoneContent.slidingSash,
                          );
                          if (!hasSlidingSash) return const SizedBox.shrink();
                          final useClassicHandle = widget.model.zones.any(
                            (z) =>
                                z.content == ZoneContent.slidingSash &&
                                z.useClassicHandle == true,
                          );
                          return Column(
                            children: [
                              const SizedBox(height: 6),
                              Container(
                                height: 1,
                                color: Colors.blueGrey.shade100.withValues(
                                  alpha: 0.5,
                                ),
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
                                        ? Localization.translate(
                                            'مقبض كلاسيكي (فتح)',
                                            lang,
                                          )
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
              })(),
              // استدعاء الدالة الفورية مباشرة
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_desktopTableMode)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 4,
                          bottom: 6,
                        ),
                        child: Text(
                          Localization.translate(
                            '⠿ اضغط مطولاً على الصف ثم اسحبه لإعادة ترتيب العناصر',
                            lang,
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white54
                                : Colors.blueGrey.shade600,
                          ),
                        ),
                      ),
                    _buildUnifiedTable(items),
                  ],
                ), // بناء الجدول الرئيسي بكل الأقسام
              ),
              const SizedBox(height: 100),
              // مساحة فارغة أسفل الجدول حتى لا يغطيها الشريط السفلي
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(
        items,
      ), // الشريط السفلي الثابت (السعر النهائي وزر الحفظ)
    );
  }

  // ==========================================================================
  // دالة: _calculateTotals ⭐
  // الغرض: حساب مجاميع التكلفة وسعر البيع لكل قسم (بروفيلات/زجاج/ستار/إكسسوارات)
  // والمجموع الكلي، حسب طريقة الحساب المختارة (نسبة مئوية/متر مربع/متر خطي).
  // ==========================================================================
  Map<String, Map<String, double>> _calculateTotals(List<BomItem> items) =>
      calculateSellingTotals(
        model: widget.model,
        items: items,
        costMethod: _costMethod,
        profitMargin: _profitMargin,
        pricePerSqm: _pricePerSqm,
        linearMeterPrice:
            _pricePerLinearMeterOverride ?? _pricePerLinearMeterFromDb,
        shutterSqmPrice: _shutterSqmPriceOverride ?? _shutterSqmPriceFromDb,
        moustiquaireSqmPrice: _moustiquaireSqmPriceFromDb,
        profileRules: _profileCalculationRules,
        obInstallFee: _obInstallFee,
        demiObInstallFee: _demiObInstallFee,
        verrouInstallFee: _verrouInstallFee,
        moteurInstallFee: _moteurInstallFee,
      );

  // ==========================================================================
  // دالة: _buildCostMethodSelector
  // تبني بطاقة (Card) تحوي: اختيار طريقة الحساب، حقل الإدخال الخاص بها،
  // إعداد الكمية، وملخص التسعير النهائي (تكلفة بدون هدر + سعر البيع).
  // ==========================================================================
  Widget _buildCostMethodSelector() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _visibleBomItems
        .where((item) {
          final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
          final qty = item.requiredQuantity > 0
              ? item.requiredQuantity
              : item.quantity;
          return hasPieces || qty > 0;
        })
        .toList(growable: false);
    final totals = _calculateTotals(items);
    final double totalCostNoWaste =
        totals['total']?['cost'] ?? 0.0; // التكلفة الصافية بدون هدر
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
              children: CostMethod.values
                  .where(
                    (method) =>
                        !_isShutterOnlyPricing ||
                        method != CostMethod.linearMeter,
                  )
                  .map((method) {
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
                      selectedColor: isDark
                          ? Colors.blue.shade900.withValues(alpha: 0.6)
                          : Colors.blue.shade100,
                      checkmarkColor: isDark
                          ? Colors.blue.shade100
                          : Colors.blue.shade800,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (isDark
                                  ? Colors.blue.shade100
                                  : Colors.blue.shade900)
                            : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    );
                  })
                  .toList(),
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
            else if (_costMethod == CostMethod.squareMeter &&
                !_isShutterOnlyPricing)
              TextField(
                controller: _pricePerSqmController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'سعر المتر المربع (دج)',
                    lang,
                  ),
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
                  labelText: Localization.translate(
                    _pricePerLinearMeterOverride == null
                        ? 'سعر المتر الخطي (دج) — من السلسلة'
                        : 'سعر المتر الخطي (دج) — تعديل يدوي',
                    lang,
                  ),
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
                          tooltip: Localization.translate(
                            'إعادة تحميل من قاعدة البيانات',
                            lang,
                          ),
                          onPressed: _loadPricesFromDb,
                        ),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  setState(() {
                    _pricePerLinearMeterOverride =
                        parsed; // أي تعديل يدوي هنا يتجاوز قيمة القاعدة
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
                  labelText: Localization.translate(
                    _shutterSqmPriceOverride == null
                        ? 'سعر المتر المربع للستار (دج) — من الكتالوج'
                        : 'سعر المتر المربع للستار (دج) — تعديل يدوي',
                    lang,
                  ),
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
            if (widget.model.hasMoustiquaireAddon) ...[
              const SizedBox(height: 10),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText:
                      'سعر المتر المربع للموستيكير (دج) — من إدارة الأسعار',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.grid_on_rounded, color: Colors.green),
                ),
                child: Text(
                  '${_moustiquaireSqmPriceFromDb.toStringAsFixed(2)} دج / م²',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Text(
                  'المساحة = عرض النافذة × ارتفاعها × الكمية. تعديل السعر يتم من إدارة الأسعار فقط.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
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
                        _updateRequestedQuantity(parsed);
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
            // بطاقة ملخص التسعير النهائي (تكلفة بدون هدر / سعر البيع المقترح)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2C) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                ),
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
                    Localization.translate('سعر التكلفة (بدون هدر)', lang),
                    '${totalCostNoWaste.toStringAsFixed(0)} ${Localization.translate('دج', lang)}',
                    Colors.orange.shade700,
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
        // The kit selector reads only from the Kits page.  A shutter
        // component with "kit" in its name is never a selectable bundle.
        final dbInstance = await SqlDatabase().db;
        if (dbInstance == null) return <Map<String, dynamic>>[];
        final rows = await dbInstance.query(
          'KitBundles',
          where: 'is_active = 1 OR is_active IS NULL',
        );
        double minimumRequiredSize = widget.model.height <= 1600
            ? 155
            : widget.model.height <= 2400
            ? 185
            : 205;
        final bladeId =
            widget.model.componentOverrides['الشرائح (Lames)']?['id'];
        if (bladeId != null) {
          final limits = await dbInstance.query(
            'ShutterBoxLimits',
            where: 'blade_id = ?',
            whereArgs: [bladeId],
            orderBy: 'box_size ASC',
          );
          final resolution = WindowModel.resolveShutterBoxFromLimits(
            windowHeight: widget.model.height,
            limits: limits,
          );
          if (resolution != null) {
            minimumRequiredSize = resolution.boxSize;
          }
        }
        final shutterKits = rows
            .map((r) => Map<String, dynamic>.from(r))
            .where(_isShutterKitBundle);
        final pricedKits = await Future.wait(
          shutterKits.map((kit) => _withShutterKitPrice(dbInstance, kit)),
        );
        return pricedKits
            .map(
              (kit) => <String, dynamic>{
                ...kit,
                'component_type': 'kit',
                'measurement': extractSizeDigits(kit['name'].toString()),
                'catalog_source': 'KitBundles',
                'minimum_required_size': minimumRequiredSize,
              },
            )
            .toList();
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
        final requiredCode = shutterKitCodeForMechanism(
          widget.model.shutterMechanism,
        );
        // The minimum comes from ShutterBoxLimits without treating a larger
        // manual choice as a new minimum. Thus a 155 drawing always offers
        // 155/185/205, while a 185 drawing offers 185/205.
        final minAllowedSize = allKits.isEmpty
            ? widget.model.shutterBoxHeight
            : (allKits.first['minimum_required_size'] as num?)?.toDouble() ??
                  widget.model.shutterBoxHeight;
        final currentKit = widget.model.componentOverrides[item.originalName];
        // عرض المقاس المناسب وكل المقاسات الأكبر فقط.
        final allowedKits = compatibleKitBundles(
          kits: allKits,
          descriptionCode: requiredCode,
          minimumSizeMm: minAllowedSize,
        );
        final currentKitId = currentKit?['id'];
        // بناء قائمة منسدلة (Popup Menu) مع علامة ✓ أمام الكيت الحالي
        return PopupMenuButton<Map<String, dynamic>>(
          icon: const Icon(
            Icons.arrow_drop_down_circle_outlined,
            color: Colors.blue,
            size: 20,
          ),
          tooltip: Localization.translate(
            'تغيير كيت الستار (المناسب ثم الأكبر)',
            Provider.of<AppSettingsProvider>(context).language,
          ),
          onSelected: (selectedKit) async {
            await _handleKitSelection(
              selectedKit,
            ); // تفويض المعالجة الفعلية لدالة _handleKitSelection
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
      final isExpanded =
          _kitGroupExpanded[kitName] ?? false; // حالة الطي/التوسعة الحالية
      final childTotalPrice = children.fold<double>(
        0,
        (sum, i) => sum + _pricedTotal(i),
      );
      final officialKitUnitPrice = _kitBundlePrices[kitName] ?? 0.0;
      // دالة داخلية: تحدد هل عنصر معين هو "رأس كيت" (وليس عنصرًا فرعيًا داخله)
      bool isKitItem(String name) =>
          name == 'كيت (Kit)' ||
          name == 'كيت فولي موتور (Kit Volet Moteur)' ||
          name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
          name == 'كيت مانيفر (Kit Manivelle)' ||
          name == 'كيت صندوق النفق (Kit Caisson Tunnel)' ||
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
      final shutterKitCode = normalizeKitDescriptionCode(
        _kitBundleMetadata[kitName]?['description'],
      );
      final isResizableShutterKit = const {'V', 'MT'}.contains(shutterKitCode);
      // العنصر الذي يمثل "رأس" هذه المجموعة (أول رأس كيت موجود، أو أول عنصر كخطة بديلة)
      final kitItem = children.firstWhere(
        (c) => isKitItem(c.originalName),
        orElse: () => children.first,
      );
      final kitQuantity = math.max(1, widget.model.quantity).toDouble();
      final isMotorKit =
          shutterKitCode == 'MT' ||
          isMatch('كيت فولي موتور (Kit Volet Moteur)', [
            'kit volet moteur',
            'kit_volet_moteur',
            'kitvoletmoteur',
            'moteur',
          ]) ||
          kitName.toLowerCase().contains('moteur');
      // إذا كان كيت موتور (أو كيت مفصول/معدل) نجمع أسعار العناصر المتبقية بداخله.
      // أما إذا كان كيت عادي كامل (مثل kit volant 155/185/205) وسعره الإجمالي مدخل > 0 نأخذ سعره،
      // وإن كان صفرًا نرجع لمجموع عناصره.
      // القاعدة: إذا وجد سعر للـ Kit (سواء حزام أو موتور أو مانيفر) نعتمد سعر الـ Kit
      // إذا لم يوجد سعر للـ Kit (سعره 0) نعتمد مجموع أسعار عناصره وقطعه الفردية
      final double totalPrice = officialKitUnitPrice > 0
          ? (officialKitUnitPrice * kitQuantity)
          : childTotalPrice;

      final double effectiveKitUnitPrice = officialKitUnitPrice > 0
          ? officialKitUnitPrice
          : (kitQuantity > 0
                ? childTotalPrice / kitQuantity
                : 0.0); // هل المجموعة مفعّلة حاليًا؟ (تُحدد من activeVariants حسب نوعها)
      final isGroupActive = isSystemOb
          ? (activeVariants['System OB'] ?? false)
          : isDemiOb
          ? (activeVariants['Demi System OB'] ?? false)
          : isVerrouCentral
          ? (activeVariants['Verrou Central'] ?? false)
          // A shutter kit is always active when it is present.  It comes
          // from KitBundles rather than the variants map, so a missing map
          // entry must not hide its change button.
          : (activeVariants[kitItem.originalName] ?? kitItem.isActive);
      // إخفاء المجموعة كليًا (بدون عرضها حتى كصف مطفأ) إذا كانت من النوع الخاص (OB/Demi/Verrou) وغير مفعّلة
      if (!isGroupActive && (isSystemOb || isDemiOb || isVerrouCentral)) {
        continue;
      }
      dynamic selectedKit = isShutterKit
          ? widget.model.componentOverrides[kitItem.originalName]
          : null;
      if (selectedKit == null && isShutterKit) {
        final seriesMatch = RegExp(r'40\s*000|67\s*000').firstMatch(kitName);
        final series = seriesMatch?.group(0)?.replaceAll(RegExp(r'\s'), '');
        for (final entry in widget.model.componentOverrides.entries) {
          final keyMatch = RegExp(r'40\s*000|67\s*000').firstMatch(entry.key);
          if (series != null &&
              keyMatch?.group(0)?.replaceAll(RegExp(r'\s'), '') == series) {
            selectedKit = entry.value;
            break;
          }
        }
      }
      final selectedKitName = selectedKit?['name']?.toString();
      // ---- بناء صف "رأس" المجموعة القابل للنقر لفتح/طي العناصر الفرعية ----
      widgets.add(
        InkWell(
          onTap: () => setState(() => _kitGroupExpanded[kitName] = !isExpanded),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                ),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // عمود الصورة: أيقونة صندوق عامة تمثل "كيت"
                  _cell(
                    Container(
                      height: 28,
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
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
                          color: isDark
                              ? Colors.purple.shade300
                              : Colors.deepPurple,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '📦 $kitName',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.purple.shade300
                                      : Colors.deepPurple,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (selectedKitName != null &&
                                  selectedKitName != kitName)
                                Text(
                                  selectedKitName,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (isShutterKit &&
                            isResizableShutterKit &&
                            isGroupActive)
                          Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: _buildKitDropdown(
                              kitItem,
                            ), // زر تغيير الكيت فقط لكيتات الستار المفعّلة
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
                  // صف المجموعة لا يمثل طول قص حقيقيًا.
                  _cell(
                    Text(
                      '-',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wActualMeters,
                  ),
                  // سعر الكيت الرسمي المخزن في كتالوج مكونات الستار أو مجموع عناصره.
                  _cell(
                    Text(
                      '${effectiveKitUnitPrice.toStringAsFixed(2)} ${Localization.translate('دج', lang)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wPrice,
                  ),
                  // إجمالي سعر الكيت الرسمي × كميته.
                  _cell(
                    Text(
                      '${totalPrice.toStringAsFixed(2)} ${Localization.translate('دج', lang)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wEstimated,
                  ),
                  // التكلفة الفعلية للمجموعة (سعر الوحدة × المطلوب الحقيقي).
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
        widgets.addAll(
          visibleChildren.map(_buildDraggableMaterialRow),
        ); // بناء صف عادي لكل عنصر فرعي عبر _row
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
      'profile': _orderedMaterialItems(
        'profile',
        items.where((i) => i.category == 'profile').toList(),
      ),
      'accessory': _orderedMaterialItems(
        'accessory',
        items
            .where(
              (i) =>
                  (i.category == 'accessory' && !isBouchonLame(i)) ||
                  (i.category == 'other'),
            )
            .toList(),
      ),
      'joint': _orderedMaterialItems(
        'joint',
        items.where((i) => i.category == 'joint').toList(),
      ),
      // كل مكونات الستار (ما عدا الجوانات) تُعرض معًا في قسم واحد
      'shutter': _orderedMaterialItems(
        'shutter',
        items
            .where(
              (i) =>
                  i.category == 'shutter' ||
                  (i.category == 'accessory' && isBouchonLame(i)),
            )
            .toList(),
      ),
      'glass': _orderedMaterialItems(
        'glass',
        items
            .where((i) => i.category == 'glass' || i.category == 'panneau')
            .toList(),
      ),
    };
    final totals = _calculateTotals(
      items,
    ); // حساب مجاميع كل قسم لعرضها في عناوين الأقسام
    // Keep one single scrolling table.  The frozen overlay duplicated a slice
    // of the rows above the real table and could become misaligned on phones.
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handleTablePageWheel,
        child: SingleChildScrollView(
          controller:
              _scrollController, // نفس الكونترولر المستخدم لمراقبة موضع التمرير
          scrollDirection:
              Axis.horizontal, // تمرير أفقي لأن الجدول أعرض من الشاشة
          child: SizedBox(
            width: _minW, // عرض ثابت = مجموع عرض كل الأعمدة
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  // صف رأس الجدول (أسماء الأعمدة)
                  // قسم البروفيلات (يظهر فقط إذا كان فيه عناصر)
                  if (groups['profile']!.isNotEmpty) ...[
                    _sectionTitle(
                      'البروفيلات',
                      Colors.blue.shade100,
                      cost: totals['profile']?['cost'],
                      selling: totals['profile']?['selling'],
                    ),
                    ...groups['profile']!.map(_buildDraggableMaterialRow),
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
                        .map(_buildDraggableMaterialRow),
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
                        .map(_buildDraggableMaterialRow),
                  ],
                  // قسم الزجاج (بدون كيتات — كل عناصره عادية)
                  if (groups['glass']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الزجاج',
                      Colors.teal.shade100,
                      cost: totals['glass']?['cost'],
                      selling: totals['glass']?['selling'],
                    ),
                    ...groups['glass']!.map(_buildDraggableMaterialRow),
                  ],
                  // قسم الجوينات (Gaskets)
                  if (groups['joint'] != null &&
                      groups['joint']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الجوينات',
                      Colors.purple.shade50,
                      cost: totals['joint']?['cost'],
                      selling: totals['joint']?['selling'],
                    ),
                    ...groups['joint']!.map(_buildDraggableMaterialRow),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // دالة: _buildMinimalOverlay
  // تبني عمودًا مصغّرًا (يحتوي فقط أسماء الأقسام والعناصر) يظهر ثابتًا على
  // يسار/يمين الشاشة عندما يكون المستخدم قد مرّر الجدول أفقيًا، لتبقى أسماء
  // العناصر مرئية دائمًا أثناء التمرير.
  // ==========================================================================
  // العمود الثابت هو قصّ من الصف الأصلي نفسه، لذلك يبقى بمحاذاة الصف
  // المقابل مهما اختلف ارتفاع النص أو عدد الأسطر.
  Widget _frozenTableSlice(Widget fullRow) {
    return SizedBox(
      width: _frozenWidth,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: _minW,
          maxWidth: _minW,
          child: IgnorePointer(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Transform.translate(
                offset: Offset(-_wImg, 0),
                child: SizedBox(width: _minW, child: fullRow),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMinimalKitGroups(List<BomItem> kitItems) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
          name == 'كيت صندوق النفق (Kit Caisson Tunnel)' ||
          name == 'كيت حزام (Kit Sangle)' ||
          name == 'كيت فولي (Kit Volet)';
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
          if (normalizedKitName == normalizedAlias) return true;
        }
        return false;
      }

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
            constraints: const BoxConstraints(minHeight: _rowMinHeight),
            width: 140,
            // Match the narrow width
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
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
                      color: isDark
                          ? Colors.purple.shade300
                          : (isGroupActive
                                ? Colors.deepPurple.shade900
                                : Colors.grey),
                      decoration: !isGroupActive
                          ? TextDecoration.lineThrough
                          : null,
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
            .where(
              (c) =>
                  !isKitItem(c.originalName) &&
                  c.originalName != 'System OB' &&
                  c.originalName != 'Demi System OB' &&
                  c.originalName != 'Verrou Central',
            )
            .toList();
        widgets.addAll(visibleChildren.map(_minimalRow));
      }
    }
    return widgets;
  }

  Widget _buildMinimalOverlay(Map<String, List<BomItem>> groups) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totals = _calculateTotals(
      groups.values.expand((group) => group).toList(),
    );

    List<Widget> section(
      String title,
      Color color,
      String key, {
      bool includeKits = false,
    }) {
      final groupItems = groups[key] ?? const <BomItem>[];
      if (groupItems.isEmpty) return const <Widget>[];
      final rows = <Widget>[
        _frozenTableSlice(
          _sectionTitle(
            title,
            color,
            cost: totals[key]?['cost'],
            selling: totals[key]?['selling'],
          ),
        ),
      ];
      if (includeKits) {
        rows.addAll(
          _buildKitGroups(
            groupItems.where((item) => item.kitGroupName != null).toList(),
          ).map(_frozenTableSlice),
        );
      }
      rows.addAll(
        groupItems
            .where((item) => !includeKits || item.kitGroupName == null)
            .map((item) => _frozenTableSlice(_row(item))),
      );
      return rows;
    }

    return Container(
      width: _frozenWidth,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF161622).withValues(alpha: 0.98)
            : Colors.white.withValues(alpha: 0.98),
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.blue.withValues(alpha: 0.35)
                : Colors.grey.shade400,
            width: 2,
          ),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _frozenTableSlice(_header()),
          ...section('البروفيلات', Colors.blue.shade100, 'profile'),
          ...section(
            'الإكسسوارات',
            Colors.orange.shade100,
            'accessory',
            includeKits: true,
          ),
          ...section(
            'مكوّنات الستار',
            Colors.purple.shade100,
            'shutter',
            includeKits: true,
          ),
          ...section('الزجاج', Colors.teal.shade100, 'glass'),
          ...section('الجوينات', Colors.purple.shade50, 'joint'),
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isScrews =
        item.name.contains('براغي') ||
        item.originalName.contains('حديد') ||
        item.originalName.contains('Renfort') ||
        item.name.contains('حديد') ||
        item.name.contains('Renfort');
    return Container(
      constraints: const BoxConstraints(minHeight: _rowMinHeight),
      width: 140,
      // Reduced width as requested
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.grey.shade200,
          ),
        ),
      ),
      child: Text(
        item.kitGroupName != null
            ? Localization.translate(item.name, lang)
            : item.getLocalizedName(_lang),
        maxLines: 3, // Allow up to 3 lines for name if it's long
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isScrews
              ? Colors.orange
              : (isDark ? Colors.white70 : Colors.black87),
          decoration: !item.isActive ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }

  Future<int?> _showQuantityDialog(BuildContext context, int currentQty) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
    double moustiquaireSelling,
    double finalSellingPrice,
  ) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Localization.translate('تفاصيل الحساب', lang),
          textDirection: TextDirection.rtl,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow(
                Localization.translate('سعر البروفيلات:', lang),
                profileSelling,
              ),
              _detailRow(
                Localization.translate('سعر الزجاج:', lang),
                glassSelling,
              ),
              _detailRow(
                Localization.translate('سعر الستار:', lang),
                shutterSelling,
              ),
              _detailRow(
                Localization.translate('سعر الإكسسوارات:', lang),
                accessorySelling,
              ),
              _detailRow('سعر الموستيكير:', moustiquaireSelling),
              const Divider(thickness: 2),
              _detailRow(
                Localization.translate('المجموع الإجمالي:', lang),
                finalSellingPrice,
                isBold: true,
              ),
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final currency = Localization.translate('دج', lang);
    final totals = _calculateTotals(items);
    final double totalCostNoWaste = totals['total']?['cost'] ?? 0.0;
    final double sellingPrice = totals['total']?['selling'] ?? 0.0;
    // سعر القطعة الواحدة = السعر الإجمالي ÷ الكمية (بحد أدنى 1 لتفادي القسمة على صفر)
    final double unitPrice = sellingPrice / math.max(1, widget.model.quantity);
    // Never create an order line with a zero/unknown selling price. This can
    // happen when a catalogue item has no price yet or when all resolved
    // components are still priced at zero.
    final canSaveAndAdd = unitPrice > 0.0 && sellingPrice > 0.0;
    return SafeArea(
      child: AnimatedContainer(
        // تحريك سلس عند تغيّر ارتفاع الشريط (طي/توسعة)
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.10),
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
                        color: isDark
                            ? const Color(0xFF2D2D44)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF3D3D5C)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isBottomBarExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_up,
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isBottomBarExpanded
                                ? Localization.translate('إخفاء', lang)
                                : Localization.translate('إعدادات السعر', lang),
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade800,
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
                      totals['moustiquaire']?['selling'] ?? 0.0,
                      sellingPrice,
                    ),
                    icon: Icon(
                      Icons.info_outline,
                      color: isDark ? Colors.blue.shade300 : Colors.blue,
                    ),
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
                  maxHeight:
                      MediaQuery.of(context).size.height *
                      0.35, // حد أقصى للارتفاع (35% من الشاشة)
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
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
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
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey.shade600,
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
                                  ? '${totalCostNoWaste.toStringAsFixed(2)} $currency'
                                  : '*** $currency',
                              // إخفاء الرقم بنجوم إذا showCostPrice == false
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade800,
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
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                            Text(
                              '${sellingPrice.toStringAsFixed(2)} $currency',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.green.shade400
                                    : Colors.green.shade700,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ],
                        ),
                      ),
                      // بطاقة اختيار طريقة الحساب كاملة (مضمّنة هنا)
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: isDark
                            ? const Color(0xFF25283D)
                            : Colors.grey.shade50,
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
                      onPressed: canSaveAndAdd
                          ? () {
                              // حفظ السعر النهائي للقطعة الواحدة في النموذج لمنع مضاعفته عند ضربه في الكمية في الفاتورة
                              widget.model.totalCost = unitPrice;
                              widget.model.manualPriceOverride = unitPrice;
                              Navigator.pop(context, true);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSaveAndAdd
                            ? (isDark
                                  ? Colors.blue.shade700
                                  : const Color(0xFF1976D2))
                            : Colors.grey,
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF1E1E2C) : Colors.blueGrey.shade800,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerCell(Localization.translate('الصورة', lang), _colImg, _wImg),
            _headerCell(
              Localization.translate('البيان', lang),
              _colName,
              _wName,
            ),
            _headerCell(Localization.translate('الكمية', lang), _colQty, _wQty),
            _headerCell(
              Localization.translate('الأمتار الفعلية المستعملة', lang),
              _colActualMeters,
              _wActualMeters,
            ),
            _headerCell(
              Localization.translate('سعر الوحدة', lang),
              _colPrice,
              _wPrice,
            ),
            _headerCell(
              Localization.translate('السعر التقديري', lang),
              _colEstimated,
              _wEstimated,
            ),
            _headerCell(
              Localization.translate('التكلفة الفعلية', lang),
              _colTotal,
              _wTotal,
            ),
            _headerCell(Localization.translate('الطول', lang), _colLen, _wLen),
            _headerCell(
              Localization.translate('اللون', lang),
              _colColor,
              _wColor,
            ),
            _headerCell(
              Localization.translate('تفعيل', lang),
              _colCheck,
              _wCheck,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(
    String title,
    String columnKey,
    double width, {
    bool isLast = false,
  }) {
    const s = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 13,
      color: Colors.white,
    );
    return _cell(
      Row(
        children: [
          Expanded(
            child: Text(title, style: s, overflow: TextOverflow.ellipsis),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) =>
                  _resizeColumn(columnKey, details.delta.dx),
              onHorizontalDragEnd: (_) => _finishColumnResize(),
              onHorizontalDragCancel: _finishColumnResize,
              child: Container(
                width: 14,
                alignment: Alignment.center,
                child: Container(
                  width: 2,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ],
      ),
      width,
      isLast: isLast,
    );
  }

  // صف عنوان قسم في الجدول (البروفيلات/الإكسسوارات/الستار/الزجاج) مع عرض التكلفة والبيع الاختياريين
  Widget _sectionTitle(
    String title,
    Color color, {
    double? cost,
    double? selling,
  }) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
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
                color: isDark
                    ? Colors.green.shade900.withValues(alpha: 0.4)
                    : Colors.green.shade700.withValues(alpha: 0.15),
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
      constraints: const BoxConstraints(minHeight: _rowMinHeight),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isLast
            ? null
            : BorderDirectional(
                end: BorderSide(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.35)
                      : Colors.grey.shade300,
                ),
              ),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  Widget _row(BomItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final localizedUnit = _localizedBomUnit(item.unit, lang);
    final currency = Localization.translate('دج', lang);
    final inactive = !item.isActive; // العنصر معطّل حاليًا
    final warning =
        item.isMissing &&
        item.isActive &&
        !_bomItemHasResolvedSelection(
          item,
        ); // العنصر مفعّل لكنه "ناقص" (لم يُربط بمكوّن فعلي بعد)
    // تمييز البراغي/الحديد بلون برتقالي مميز
    final isScrews =
        item.originalName.contains('براغي') ||
        item.originalName.contains('حديد') ||
        item.originalName.contains('Renfort') ||
        item.name.contains('حديد') ||
        item.name.contains('Renfort');
    final bool isKitElement =
        item.kitGroupName != null; // هل هذا الصف عنصر فرعي داخل كيت
    final normalizedUnit = item.unit.trim().toLowerCase();
    final isGlassSquareMeter =
        (item.category == 'glass' || item.category == 'panneau') &&
        (normalizedUnit == 'م²' ||
            normalizedUnit == 'm²' ||
            normalizedUnit == 'm2' ||
            normalizedUnit == 'sqm');
    String formatQuantity(double value) {
      if ((value - value.roundToDouble()).abs() < 0.000001) {
        return value.round().toString();
      }
      return value.toStringAsFixed(2);
    }

    final quantityLabel = isGlassSquareMeter
        ? '${item.quantity.toStringAsFixed(2)} $localizedUnit'
        : '${formatQuantity(item.quantity)} $localizedUnit';
    return Container(
      decoration: BoxDecoration(
        color: inactive
            ? (isDark
                  ? Colors.red.shade900.withValues(alpha: 0.3)
                  : Colors.red.shade50) // خلفية حمراء خفيفة للعناصر المعطّلة
            : (isKitElement
                  ? (isDark
                        ? Colors.blue.shade900.withValues(alpha: 0.3)
                        : Colors.blue.shade50.withValues(
                            alpha: 0.5,
                          )) // خلفية زرقاء خفيفة لعناصر الكيت الفرعية
                  : (isDark ? const Color(0xFF1E1E2C) : Colors.white)),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.grey.shade200,
          ),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // عمود الصورة: أيقونة مختلفة حسب كون العنصر جزءًا من كيت أو لا
            _cell(
              SectionImageWidget(
                code: item.profileCode,
                name: item.name,
                imagePath: item.imagePath,
                size: isKitElement ? 32.0 : 28.0,
                fallbackIcon: isKitElement ? Icons.extension : Icons.image,
                fallbackColor: isKitElement
                    ? (isDark ? Colors.blue.shade300 : Colors.blue.shade700)
                    : Colors.grey,
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
                          isKitElement
                              ? Localization.translate(
                                  item.name.split('\n').first,
                                  lang,
                                )
                              : item.getLocalizedName(_lang),
                          style: TextStyle(
                            fontSize: isKitElement ? 13.5 : 12,
                            fontWeight: FontWeight.bold,
                            color: isScrews
                                ? Colors.orange
                                : (isKitElement
                                      ? (isDark
                                            ? Colors.blue.shade300
                                            : Colors.blue.shade900)
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87)),
                            decoration: inactive
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (!isKitElement &&
                            item.catalogItemId != null &&
                            (item.inventoryItemType ?? '').isNotEmpty)
                          Builder(
                            builder: (context) {
                              // Keep stock visibility stable. A missing row
                              // in CurrentStock means available quantity is
                              // zero; it must not make the whole line vanish.
                              final stock = _mainStockFor(item) ?? 0.0;
                              return Text(
                                '${Localization.translate('المستودع الرئيسي', lang)}: ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2)} $localizedUnit',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: stock <= 0
                                      ? Colors.red.shade700
                                      : (isDark
                                            ? Colors.teal.shade200
                                            : Colors.teal.shade700),
                                ),
                              );
                            },
                          ),
                        if (isKitElement && item.name.contains('\n'))
                          Text(
                            item.name.split('\n').skip(1).join(' • '),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.normal,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        // لعناصر الكيت: عرض الكمية والوحدة تحت الاسم مباشرة
                        if (isKitElement)
                          Text(
                            '${Localization.translate('الكمية:', lang)} ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} $localizedUnit',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.blue.shade200
                                  : Colors.blue.shade700,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          )
                        // لغير عناصر الكيت: عرض الاسم الأصلي (الثانوي) إن اختلف عن الاسم المترجم
                        else ...[
                          (() {
                            final localizedTitle = item.getLocalizedName(_lang);
                            final parts = item.name.split('\n');
                            final namePart = parts[0];
                            final rawSubparts = parts.length > 1
                                ? parts.sublist(1)
                                : <String>[
                                    if (item.profileCode != null &&
                                        item.profileCode!.trim().isNotEmpty &&
                                        item.profileCode!.trim() != namePart)
                                      item.profileCode!.trim(),
                                  ];
                            final subparts = rawSubparts.where((subText) {
                              final trimmed = subText.trim();
                              if (trimmed.isEmpty) return false;
                              final lower = trimmed.toLowerCase();
                              if (trimmed.contains('المطلوب الفعلي') ||
                                  lower.contains('besoin réel') ||
                                  lower.contains('actual requirement')) {
                                return false;
                              }
                              // Don't show standalone redundant labels that match or repeat part of the title
                              if (lower == 'renforcé' ||
                                  lower == 'renforce' ||
                                  lower == '- renforcé' ||
                                  lower == '- renforce' ||
                                  lower == 'central' ||
                                  lower == 'latéral' ||
                                  lower == 'lateral' ||
                                  lower == 'coulissant' ||
                                  lower == 'dormant') {
                                return false;
                              }
                              if (lower == localizedTitle.toLowerCase())
                                return false;
                              // If French language, hide pure Arabic subparts
                              if (_lang == 'fr' && _hasArabic(trimmed)) {
                                return false;
                              }
                              return true;
                            }).toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (namePart != item.originalName &&
                                    (_lang == 'ar' ||
                                        item.category == 'glass' ||
                                        !_hasArabic(namePart)))
                                  Text(
                                    namePart,
                                    style: TextStyle(
                                      fontSize: item.category == 'glass'
                                          ? 9.0
                                          : 10,
                                      fontWeight: FontWeight.normal,
                                      color: item.category == 'glass'
                                          ? (isDark
                                                ? Colors.grey.shade400
                                                : Colors.grey.shade600)
                                          : (isDark
                                                ? Colors.white54
                                                : Colors.grey.shade700),
                                      decoration: inactive
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ...subparts.map(
                                  (subText) => Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      BomItem.localizeSubText(subText, _lang),
                                      style: TextStyle(
                                        fontSize: 9.0,
                                        fontWeight: FontWeight.normal,
                                        color: isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                        height: 1.1,
                                        decoration: inactive
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
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
                              item.getLocalizedCuttingList(_lang) ??
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
                  if (item.isActive &&
                      item.originalName != 'أغطية الشفرات (Bouchons Lames)')
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
                quantityLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              _wQty,
            ),
            // مجموع أطوال قطع القص الفعلية، وليس عدد القضبان المقرّب.
            _cell(
              Text(
                _actualUsedMetersFor(item) == null
                    ? '-'
                    : '${formatQuantity(_actualUsedMetersFor(item)!)}m',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              _wActualMeters,
            ),
            // عمود سعر الوحدة + زر تعديل السعر يدويًا (يفتح _showEditPriceDialog)
            _cell(
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_isExcludedFromPricing(item) ? 0.0 : item.unitPrice} $currency',
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
            // Purchase estimate uses whole stock units; real cost below uses
            // fractional consumption (for example 0.75 bars).
            _cell(
              Text(
                '${(_isExcludedFromPricing(item) || !item.isActive
                    ? 0.0
                    : item.category == 'glass'
                    ? item.total
                    : item.purchaseQuantity * item.unitPrice).toStringAsFixed(2)} $currency',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                  decoration: inactive ? TextDecoration.lineThrough : null,
                ),
              ),
              _wEstimated,
            ),
            // مبلغ التكلفة الفعلية: سعر الوحدة × المطلوب الحقيقي.  لا نعرض
            // «المطلوب الحقيقي» ككمية مستقلة لأن هذا العمود للتسعير النقدي.
            _cell(
              Text(
                '${_pricedTotal(item).toStringAsFixed(2)} $currency',
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
                item.category == 'glass'
                    ? '-'
                    : ((item.category == 'accessory' ||
                                  item.category == 'other') &&
                              (item.colorName ?? '').trim().isEmpty
                          ? ''
                          : (item.colorName ?? '-')),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
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
                  : const SizedBox.shrink(),
              // عنصر غير تفاعلي: لا يوجد Checkbox
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
    final swapTarget = _resolveBomSwapTarget(item);
    String pType = swapTarget.profileType;
    String pCategory = swapTarget.category;
    final explicitRoleKey = (item.roleKey ?? '').trim();
    final explicitSelectorType = (item.selectorType ?? '').trim();
    final usesExplicitCatalogSelector =
        pCategory != 'shutter' &&
        (explicitRoleKey.isNotEmpty || explicitSelectorType.isNotEmpty);
    final rowLooksPlinthe =
        item.originalName.toLowerCase().contains('plinthe') ||
        item.originalName.contains('بلانت') ||
        pType.toLowerCase().contains('plinthe') ||
        pType.contains('بلانت');
    final rowRoleText =
        '${item.originalName} ${item.roleKey ?? ''} ${item.selectorType ?? ''}'
            .toLowerCase();
    final isSlidingLateralRow = explicitRoleKey.isNotEmpty
        ? explicitRoleKey.startsWith('sash_lateral') ||
              explicitRoleKey == 'lateral'
        : rowRoleText.contains('sash_lateral') ||
              rowRoleText.contains('sash lateral') ||
              rowRoleText.contains('قائم جانبي');
    final isSlidingCentralRow = explicitRoleKey.isNotEmpty
        ? explicitRoleKey.startsWith('sash_central') ||
              explicitRoleKey == 'central'
        : rowRoleText.contains('sash_central') ||
              rowRoleText.contains('sash central') ||
              rowRoleText.contains('قائم وسطي');
    final isSlidingSlimRow =
        explicitRoleKey == 'montant_central_slim' ||
        explicitRoleKey == 'sash_central_slim' ||
        explicitSelectorType == 'montant_central_slim' ||
        rowRoleText.contains('montant slim') ||
        rowRoleText.contains('montant_central_slim') ||
        rowRoleText.contains('مونتوسليم') ||
        rowRoleText.contains('قائم وسطي سليم');
    final isSlidingSlimComplementRow =
        explicitRoleKey == 'complement_haut_base' ||
        explicitSelectorType == 'complement_haut_base' ||
        rowRoleText.contains('complement_haut_base') ||
        rowRoleText.contains('complément haut') ||
        rowRoleText.contains('complement haut') ||
        rowRoleText.contains('مكمل علوي') ||
        rowRoleText.contains('taquet slim');
    // A montant can be changed in both directions. Restricting a reinforced
    // row to the reinforced role made the regular profile disappear from the
    // selector, so the user could never switch it back to normal.
    final dialogRoleKeys = rowLooksPlinthe
        ? const <String>['plant']
        // A complement name can include "Slim", but it is a different
        // profile role. It must win over the Slim montant test so its change
        // dialog never lists central-montant candidates.
        : isSlidingSlimComplementRow
        ? const <String>['complement_haut_base']
        : isSlidingSlimRow
        // Some existing series were saved under the original alias
        // `sash_central_slim`; both names represent the same selectable Slim
        // montant and must therefore resolve in the replacement dialog.
        ? const <String>['montant_central_slim', 'sash_central_slim']
        : isSlidingLateralRow
        ? const <String>['sash_lateral', 'sash_lateral_reinforced']
        : isSlidingCentralRow
        ? const <String>['sash_central', 'sash_central_reinforced']
        : explicitRoleKey.isEmpty
        ? const <String>[]
        : <String>[explicitRoleKey];
    final espagnoletteLengthMatch = RegExp(
      r'(\d+(?:[.,]\d+)?)',
    ).firstMatch(item.originalName);
    final double? maxEspagnoletteLength = espagnoletteLengthMatch == null
        ? null
        : double.tryParse(
            espagnoletteLengthMatch.group(1)!.replaceAll(',', '.'),
          );
    bool isFrameClicked = swapTarget.isFrame;
    bool isSashClicked = swapTarget.isSash;
    bool isSideCoverClicked = swapTarget.isSideCover;
    // ---- التعرف على الإطار: إما بالاسم الثابت أو بمطابقة الاسم المعروض الحالي ----
    if (pType == 'الإطار (Frame)' || pType == 'الإطار (Cadre)') {
      isFrameClicked = true;
    } else if (widget.model.frameOverride != null) {
      String frameDisplay =
          '${widget.model.frameOverride!['code'] ?? ''} - ${widget.model.frameOverride!['name']}'
              .trim();
      if (frameDisplay.startsWith('- ')) {
        frameDisplay = frameDisplay.substring(
          2,
        ); // إزالة "- " إذا لم يكن هناك كود
      }
      if (pType == frameDisplay) isFrameClicked = true;
    }
    // ---- نفس المنطق للظلفة ----
    final pTypeLower = pType.toLowerCase();
    if (pType == 'الظلفة (Sash)' ||
        pType == 'الظلفة المنزلقة (Sliding Sash)' ||
        pTypeLower.contains('sliding sash')) {
      isSashClicked = true;
    } else if (widget.model.sashOverride != null) {
      String sashDisplay =
          '${widget.model.sashOverride!['code'] ?? ''} - ${widget.model.sashOverride!['name']}'
              .trim();
      if (sashDisplay.startsWith('- ')) sashDisplay = sashDisplay.substring(2);
      if (pType == sashDisplay) isSashClicked = true;
    }
    if (!isSashClicked && widget.model.slidingSashOverride != null) {
      String sashDisplay =
          '${widget.model.slidingSashOverride!['code'] ?? ''} - ${widget.model.slidingSashOverride!['name']}'
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
      final isSlidingFrameSelection =
          swapTarget.drawingMode == AccessoryDrawingMode.sliding ||
          (swapTarget.drawingMode == null &&
              widget.model.usesSlidingPrimaryProfiles);
      // فتح نافذة اختيار بروفيل من نوع "frame" ضمن السلسلة النشطة والمادة الصحيحة (PVC/ألمنيوم)
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'frame',
          category: 'profile',
          seriesId: _seriesIdForSwapTarget(item, swapTarget),
          materialType: _materialTypeForSwapTarget(item, swapTarget),
          hasShutter: widget.model.hasShutter,
          isCaissonTunnel: widget.model.isCaissonTunnel,
          hasSideCovers: widget.model.hasSideCovers,
          multiFrameDrawing: widget.model.getFrameRects().length > 1,
          accessoryDrawingMode: swapTarget.drawingMode,
          roleKeys: dialogRoleKeys,
          hasSimpleGlassForReducer: widget.model.hasSimpleGlassForReducer,
          hasDoubleGlassForRules: widget.model.hasDoubleGlassForRules,
          targetThicknessMm: item.targetThicknessMm,
          mainWarehouseStock: _mainWarehouseStock,
          stockColorId: _itemColorId(item),
        ),
      );
      if (selected != null && mounted) {
        double price = 0.0;
        if (widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(
            selected['id'],
            colorId,
          ); // جلب السعر حسب اللون
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;
        setState(() {
          // تحديث الإطار حسب وضع النظام (منزلق/عادي)
          widget.model.applyFrameOverride(
            mutableSelected,
            sliding: isSlidingFrameSelection,
            manualSelection: true,
          );
          widget.model.refreshUI();
        });
        await widget.model.syncFrameReinforcement();
        await _refreshVisibleBomItems();
      }
      return; // إنهاء الدالة هنا (لا تكمل باقي منطق التبديل العام)
    }
    // ===================== حالة: ضغطة زر الظلفة =====================
    if (isSashClicked) {
      final isSlidingSelection =
          swapTarget.drawingMode == AccessoryDrawingMode.sliding ||
          item.originalName.toLowerCase().contains('sliding sash') ||
          item.originalName.contains('منزلقة');
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'sash',
          category: 'profile',
          seriesId: _seriesIdForSwapTarget(item, swapTarget),
          materialType: _materialTypeForSwapTarget(item, swapTarget),
          accessoryDrawingMode: swapTarget.drawingMode,
          roleKeys: dialogRoleKeys,
          hasSimpleGlassForReducer: widget.model.hasSimpleGlassForReducer,
          hasDoubleGlassForRules: widget.model.hasDoubleGlassForRules,
          targetThicknessMm: item.targetThicknessMm,
          mainWarehouseStock: _mainWarehouseStock,
          stockColorId: _itemColorId(item),
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
                _seriesIdForSwapTarget(item, swapTarget),
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
          widget.model.applySashOverride(
            mutableSelected,
            sliding: isSlidingSelection,
            manualSelection: true,
          );
          widget.model.refreshUI();
        });
        await _refreshVisibleBomItems();
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
          seriesId: _seriesIdForSwapTarget(item, swapTarget),
          materialType: _materialTypeForSwapTarget(item, swapTarget),
          accessoryDrawingMode: swapTarget.drawingMode,
          roleKeys: dialogRoleKeys,
          hasSimpleGlassForReducer: widget.model.hasSimpleGlassForReducer,
          hasDoubleGlassForRules: widget.model.hasDoubleGlassForRules,
          targetThicknessMm: item.targetThicknessMm,
          mainWarehouseStock: _mainWarehouseStock,
          stockColorId: _itemColorId(item),
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
          widget.model.selectedSideCover = AluminumSection.fromMap(
            mutableSelected,
          );
          widget.model.componentOverrides['الغطاء الجانبي (Side Cover)'] =
              mutableSelected;
          if (item.originalName != 'الغطاء الجانبي (Side Cover)') {
            widget.model.componentOverrides[item.originalName] =
                mutableSelected;
          }
          widget.model.refreshUI();
        });
        await _refreshVisibleBomItems();
      }
      return;
    }
    // ===================== الحالة العامة: تحويل اسم العنصر إلى "نوع بحث" (pType) مناسب =====================
    // كل الحالات التالية تُغيّر pType/pCategory إلى صيغة يفهمها ProfileSelectorDialog للبحث
    // الجوانات (Joints)
    if (!usesExplicitCatalogSelector) {
      if (pType.contains('جوان') || pType.toLowerCase().contains('joint')) {
        pCategory = 'joint';
        if (pType.contains('بروس') || pType.toLowerCase().contains('bross')) {
          pType = ('Joint bross');
        }
      } else if (pType.toLowerCase().contains('clamp') ||
          pType.toLowerCase().contains('clam') ||
          pType.contains('كلامب') ||
          pType.contains('كلام') ||
          pType.contains('كلان')) {
        pCategory = 'accessory';
        pType = 'clamp';
      } else if (pType.contains('براغي')) {
        pCategory = 'accessory';
        if (pType.contains('براغي حديد الدعم')) {
          pType = 'is_renfort_screw';
        } else if (pType.contains('براغي بوشون باتمو')) {
          pType = 'is_bouchon_batmo_screw';
        } else if (pType.contains('براغي الباتمو')) {
          pType = 'is_batmo_screw';
        } else if (pType.contains('براغي الكيت')) {
          pType = 'is_kit_screw';
        } else if (pType.contains('براغي المانيفال')) {
          pType = 'is_manivelle_screw';
        } else if (pType.contains('براغي المحرك')) {
          pType = 'is_moteur_screw';
        } else if (pType.contains('براغي الصندوق')) {
          pType = 'is_caisson_screw';
        } else if (pType.contains('براغي التجميع')) {
          pType = 'is_assembly_screw';
        } else if (pType.contains('براغي التركيب')) {
          pType = 'is_installation_screw';
        } else if (pType.contains('براغي الإكسسوارات')) {
          pType = 'is_accessory_screw';
        }
      } else if (pCategory == 'accessory') {
        if (pType.contains('قاش دوبل') || pType.contains('Gache Double')) {
          pType = 'is_gache_double';
        } else if (pType.contains('قاش سامبل') ||
            pType.contains('Gache Simple')) {
          pType = 'is_gache_simple';
        } else if (pType.contains('قاش بورت') ||
            pType.contains('Gache Porte') ||
            pType.contains('Gâche Porte')) {
          pType = 'is_gache_porte';
        } else if (pType.contains('كاش كوليسون') ||
            pType.toLowerCase().contains('gache coulisse') ||
            pType.toLowerCase().contains('gâche coulisse') ||
            pType.toLowerCase().contains('gache coulissant') ||
            pType.toLowerCase().contains('gâche coulissant')) {
          pType = 'كاش كوليسون';
        } else if (pType.toLowerCase().contains('clamp') ||
            pType.toLowerCase().contains('clam') ||
            pType.contains('كلامب') ||
            pType.contains('كلام') ||
            pType.contains('كلان')) {
          pType = 'clamp';
        } else if (pType.contains('مقبض الباب (Poignée Porte à Clé)')) {
          pType = 'is_poign_clef';
        } else if (pType.contains('مقبض الباب Condamnation')) {
          pType = 'is_poign_condamnation';
        } else if (pType.contains('الأسطوانة') || pType.contains('Canon')) {
          pType = 'is_canon';
        } else if (pType.contains('قفل بمفتاح') || pType.contains('Clef')) {
          pType = 'is_lock_clef';
        } else if (pType.contains('Serrure Condamnation') ||
            pType.contains('قفل الباب Condamnation') ||
            pType.contains('Condamnation')) {
          pType = 'is_lock_condamnation';
        } else if (pType.contains('قفل الباب') || pType.contains('Serrure')) {
          pType = 'is_lock_clef';
        } else if (pType.contains('اسبانيوليت') ||
            pType.contains('إسبانيوليت')) {
          pType = 'اسبانيوليت';
        } else if (pType.contains('مفاصل') || pType.contains('Hinges')) {
          pType = 'مفاصل';
        } else if ((pType.contains('فيرو') || pType.contains('Verrou')) &&
            !pType.contains('Central')) {
          pType = 'فيرو';
        } else if (pType.toLowerCase().contains('poignée coulissante') ||
            pType.toLowerCase().contains('poignee coulissante') ||
            pType.contains('مقبض منزلق')) {
          pType = 'poignee coulissante';
        } else if (pType.contains('المقبض (Handle)') ||
            pType.contains('مقبض نافذة') ||
            pType.toLowerCase().contains('poignée fenêtre') ||
            pType.toLowerCase().contains('poignee fenetre')) {
          pType = 'is_window_handle';
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
      }
    }
    if (pCategory == 'shutter') {
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
    final selectedBladeName = bladeObj?['name']?.toString();
    final selectedBladeIsX3d = _isX3dBlade(bladeObj);
    final selectedMotor = widget.model.componentOverrides['المحرك (Moteur)'];
    final motorDiameter = selectedMotor == null
        ? null
        : shutterComponentDiameter(selectedMotor);
    final accessoryDrawingMode = swapTarget.drawingMode;
    final functionalSlidingProfile =
        isSlidingSlimRow || isSlidingSlimComplementRow;
    // فتح نافذة الاختيار العامة بالمعطيات المحسوبة أعلاه
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProfileSelectorDialog(
        profileType: pType,
        category: pCategory,
        seriesId: functionalSlidingProfile
            ? (widget.model.activeSlidingSeries?.id ??
                  _seriesIdForSwapTarget(item, swapTarget))
            : _seriesIdForSwapTarget(item, swapTarget),
        materialType: _materialTypeForSwapTarget(item, swapTarget),
        hasShutter: widget.model.hasShutter,
        isCaissonTunnel: widget.model.isCaissonTunnel,
        hasSideCovers: widget.model.hasSideCovers,
        // The explicit role already fixes this to the active sliding series.
        // Do not additionally reject a legacy role row whose old scope field
        // was saved as opening/auto.
        accessoryDrawingMode: functionalSlidingProfile
            ? null
            : accessoryDrawingMode,
        roleKeys: dialogRoleKeys,
        windowHeight: widget.model.height,
        targetSize: widget.model.shutterBoxHeight,
        kitDescriptionCode: pCategory == 'shutter' && pType == 'كيت'
            ? shutterKitCodeForMechanism(widget.model.shutterMechanism)
            : null,
        maxAccessoryLength: pType == 'اسبانيوليت'
            ? maxEspagnoletteLength
            : null,
        bladeId: bladeId,
        selectedBladeName: selectedBladeName,
        selectedBladeIsX3d: selectedBladeIsX3d,
        motorDiameter: motorDiameter,
        hasSimpleGlassForReducer: widget.model.hasSimpleGlassForReducer,
        hasDoubleGlassForRules: widget.model.hasDoubleGlassForRules,
        targetThicknessMm: item.targetThicknessMm,
        mainWarehouseStock: _mainWarehouseStock,
        stockColorId: _itemColorId(item),
      ),
    );
    if (selected != null && mounted) {
      try {
        double price = 0.0;
        final db = SqlDatabase();
        // حساب السعر: بروفيل حسب اللون، وإلا السعر العام المباشر
        final settings = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        );
        if (pCategory == 'profile' && widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          price = await db.getSectionPrice(selected['id'], colorId);
          if (price <= 0) {
            price = _safeDouble(selected['price_dzd'] ?? selected['price']);
          }
          if (settings.applyPurchasePricesToCostTable) {
            final purchasePrice = await db.getLatestPurchasePrice(
              itemId: (selected['id'] as num).toInt(),
              itemType: 'Sections',
              colorId: colorId,
            );
            if (purchasePrice != null && purchasePrice > 0) {
              price = purchasePrice;
            }
          }
        } else if (pCategory == 'accessory') {
          final dbInstance = await db.db;
          price = dbInstance == null
              ? _safeDouble(selected['price_dzd'] ?? selected['price'])
              : await _resolveSelectedAccessoryPrice(dbInstance, selected);
        } else {
          price = _safeDouble(selected['price_dzd'] ?? selected['price']);
          if (settings.applyPurchasePricesToCostTable &&
              selected['id'] != null) {
            final purchasePrice = await db.getLatestPurchasePrice(
              itemId: (selected['id'] as num).toInt(),
              itemType: pCategory == 'shutter'
                  ? 'ShutterComponents'
                  : pCategory,
              colorId: widget.model.selectedDbColor?['id'],
            );
            if (purchasePrice != null && purchasePrice > 0) {
              price = purchasePrice;
            }
          }
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['manual_selection'] = true;
        mutableSelected['user_selected'] = true;
        mutableSelected['automatic_selection'] = false;
        if (price > 0) mutableSelected['calculated_price'] = price;
        final isKitItem =
            !_isScrewBomName(item.originalName) &&
            (item.originalName.contains('Kit') ||
                item.originalName.contains('كيت'));
        final isCaisson = item.originalName == 'الصندوق (Caisson)';
        // إذا كان العنصر المُبدَّل هو "الصندوق"، حدد وضع التونيل حسب id خاص (-999 يعني تونيل)
        if (isCaisson) {
          if (mutableSelected['id'] == -999) {
            widget.model.toggleCaissonTunnel(true);
          } else {
            widget.model.toggleCaissonTunnel(false);
            final selectedBoxSize = double.tryParse(
              getComponentSize(mutableSelected) ?? '',
            );
            if (selectedBoxSize != null && selectedBoxSize > 0) {
              mutableSelected['manual_override'] = true;
              widget.model.setManualShutterBoxHeight(selectedBoxSize);
            }
          }
        }
        Map<String, dynamic>?
        companionCaissonToSet; // صندوق مرافق يجب ضبطه إذا اخترنا كيتًا
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
                  activeKitKeys = ['كيت فولي (Kit Volet)'];
                }
                for (var kitKey in activeKitKeys) {
                  final compRes = await dbInstance.query(
                    'KitBundles',
                    where: 'is_active = 1 OR is_active IS NULL',
                  );
                  for (var row in compRes) {
                    final rowMap = Map<String, dynamic>.from(row);
                    if (!isShutterKitForMechanism(
                      rowMap,
                      widget.model.shutterMechanism,
                    )) {
                      continue;
                    }
                    final selectedSize = double.tryParse(selectedDigits);
                    final kitSize = kitBundleSizeMm(rowMap);
                    if (selectedSize != null &&
                        kitSize != null &&
                        (kitSize - selectedSize).abs() <= 0.5) {
                      // Found a KitBundles row matching the new caisson size.
                      final matchedCompanion = await _withShutterKitPrice(
                        dbInstance,
                        rowMap,
                      );
                      matchedCompanion['catalog_source'] = 'KitBundles';
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
              if (item.originalName == 'الشرائح (Lames)') {
                final requiredTrackSize = getBladeTrackSize(mutableSelected);
                final res = await dbInstance.query(
                  'ShutterComponents',
                  where:
                      "LOWER(TRIM(component_type)) IN ('track', 'coulisse', 'coulisses', 'glissiere') AND (is_active = 1 OR is_active IS NULL)",
                );
                for (var row in res) {
                  if (requiredTrackSize != null &&
                      getComponentMeasurementKey(row) == requiredTrackSize) {
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
          companionAxe = await _findCompatibleShutterAxis(
            blade: mutableSelected,
            motor: widget.model.componentOverrides['المحرك (Moteur)'],
          );
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
          companionBouchonLame = await _findBladeEndCap(mutableSelected);
        }
        // Changing the motor can change which axis is compatible.  The blade
        // relation remains the first filter, before the motor diameter.
        if (item.originalName == 'المحرك (Moteur)') {
          companionAxe = await _findCompatibleShutterAxis(
            blade: widget.model.componentOverrides['الشرائح (Lames)'],
            motor: mutableSelected,
          );
        }
        // ---- تطبيق كل التغييرات: إما مسار الكيت (معالجة خاصة) أو المسار العام لتحديث componentOverrides ----
        if (isKitItem) {
          await _handleKitSelection(
            mutableSelected,
          ); // كيت: نمرر المعالجة كاملة لدالة مخصصة
        } else {
          final overrideKey =
              swapTarget.overrideKey ?? item.overrideKey ?? item.originalName;
          setState(() {
            // Bidirectional synchronization between B.O.M. profile selection and drawer stiles/montants checkboxes
            final selectedType = swapTarget.profileType.toLowerCase();
            final selectionHint = [
              selectedType,
              item.originalName,
              item.overrideKey ?? '',
              swapTarget.overrideKey ?? '',
            ].join(' ').toLowerCase();
            if (isSlidingSlimComplementRow) {
              // This is the dedicated 10 cm top/bottom Slim complement, not
              // the Slim central montant. Store its choice under the stable
              // calculation key used when the BOM is rebuilt.
              widget
                      .model
                      .componentOverrides['مكمل علوي وسفلي للمونتوسليم 10 سم (Complément haut et bas)'] =
                  mutableSelected;
              widget
                      .model
                      .componentOverrides['قطاع وصلة المونتوسليم 10 سم (Taquet Slim 10cm)'] =
                  mutableSelected;
              widget.model.componentOverrides[overrideKey] = mutableSelected;
            } else if (isSlidingSlimRow) {
              // Slim is its own selected profile. Treating it as the normal
              // central montant overwrote the regular override and made the
              // Slim row vanish after the next BOM refresh.
              widget.model.applySlidingMontantSlimOverride(
                mutableSelected,
                manualSelection: true,
              );
            } else if (isSlidingLateralRow ||
                (!isSlidingCentralRow &&
                    (selectedType.contains('lateral') ||
                        selectionHint.contains('montant lateral') ||
                        selectionHint.contains('sash lateral') ||
                        item.originalName.contains('Sash Lateral') ||
                        item.originalName.contains('قائم جانبي') ||
                        item.originalName == 'قائم جانبي (Lateral)'))) {
              widget.model.applySlidingMontantOverride(
                mutableSelected,
                central: false,
                manualSelection: true,
              );
            } else if (isSlidingCentralRow ||
                selectedType.contains('central') ||
                selectionHint.contains('montant central') ||
                selectionHint.contains('sash central') ||
                item.originalName.contains('Sash Central') ||
                item.originalName.contains('قائم وسطي') ||
                item.originalName == 'قائم وسطي (Central)') {
              widget.model.applySlidingMontantOverride(
                mutableSelected,
                central: true,
                manualSelection: true,
              );
            } else {
              final normalizedPType = pType.toLowerCase();
              final isParcloseSelection =
                  pCategory == 'profile' &&
                  (normalizedPType == 'parclose' ||
                      normalizedPType.contains('parclose') ||
                      normalizedPType.contains('باكيت') ||
                      normalizedPType.contains('بيركلوز'));
              if (isParcloseSelection) {
                // A BOM row represents the profile family, not one physical
                // occurrence. Replace the old simple/double/sliding aliases
                // so every matching parclose in the drawing uses the choice.
                for (final key in widget.model.componentOverrides.keys.where((
                  key,
                ) {
                  final lower = key.toLowerCase();
                  return lower.contains('parclose') ||
                      key.contains('باكيت') ||
                      key.contains('بيركلوز');
                }).toList()) {
                  widget.model.componentOverrides.remove(key);
                }
                widget.model.componentOverrides['باكيت الزجاج (Parclose)'] =
                    mutableSelected;
              } else {
                widget.model.componentOverrides[overrideKey] =
                    mutableSelected; // حفظ الاختيار الجديد كـ override
              }
            }
            widget.model
                .updateGlassGasket(); // تحديث جوان الزجاج (إن كان مرتبطًا بتغييرات البروفيل)
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
            if (item.originalName == 'الشرائح (Lames)') {
              if (companionBouchonLame == null) {
                widget.model.componentOverrides.remove(
                  'أغطية الشفرات (Bouchons Lames)',
                );
              } else {
                widget
                        .model
                        .componentOverrides['أغطية الشفرات (Bouchons Lames)'] =
                    companionBouchonLame;
              }
            }
            widget.model.refreshUI();
          });
          if (_swapSelectionNeedsDefaultRefresh(item, swapTarget)) {
            // Only shutter families need a companion/default refresh. Profile
            // and accessory swaps must remain immediate and user-owned.
            await _fetchDefaults();
          } else {
            await _refreshVisibleBomItems();
          }
        }
      } catch (e) {
        print(
          "Error handling swap selection: $e",
        ); // تسجيل الخطأ دون كسر الشاشة
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
    Map<String, dynamic>? override = _componentOverrideForBom(item);
    if (override == null) {
      final origLower = item.originalName.toLowerCase();
      if (origLower.contains('إطار') ||
          origLower.contains('frame') ||
          origLower.contains('cadre')) {
        override =
            widget.model.frameOverride ?? widget.model.slidingFrameOverride;
      } else if (origLower.contains('ظلف') ||
          origLower.contains('sash') ||
          origLower.contains('ouvrant')) {
        override =
            widget.model.sashOverride ?? widget.model.slidingSashOverride;
      } else if (origLower.contains('side_cover') ||
          origLower.contains('تغطية') ||
          origLower.contains('الغطاء الجانبي')) {
        override = widget.model.sideCoverOverride;
      }
    }

    // جلب المعرف الحقيقي سواء من catalogItemId أو من الـ override
    final int? dbId =
        item.catalogItemId ??
        (override?['id'] is num
            ? (override!['id'] as num).toInt()
            : int.tryParse('${override?['id'] ?? ''}'));

    final colorId = item.category == 'accessory'
        ? _selectedAccessoryColorId()
        : (widget.model.selectedDbColor?['id'] is num
              ? (widget.model.selectedDbColor!['id'] as num).toInt()
              : int.tryParse('${widget.model.selectedDbColor?['id'] ?? ''}'));

    String? errorMsg;
    bool success = false;
    try {
      if (item.category == 'profile') {
        if (dbId != null) {
          if (colorId != null) {
            await SqlDatabase().setSectionColorPrice(dbId, colorId, newPrice);
          } else {
            // إذا لم يكن هناك لون محدد للبروفيل، نحدث السعر الافتراضي في جدول Sections مباشرة
            await db.update(
              'Sections',
              {'price': newPrice, 'price_dzd': newPrice},
              where: 'id = ?',
              whereArgs: [dbId],
            );
          }
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final controller = TextEditingController(text: '${item.unitPrice}');
    bool saveToDb = true; // ✅ تم جعله مفعلاً ومحدداً افتراضياً

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text(
                '${Localization.translate('تعديل سعر', lang)} ${item.getLocalizedName(_lang)}',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'السعر الجديد (دج)',
                        lang,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: Text(
                      Localization.translate(
                        'حفظ في قاعدة البيانات أيضاً',
                        lang,
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                    value: saveToDb,
                    onChanged: (val) {
                      setStateDialog(() {
                        saveToDb = val ?? true;
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
                      final overrideKey = item.overrideKey ?? item.originalName;
                      final existing =
                          widget.model.componentOverrides[overrideKey] is Map
                          ? Map<String, dynamic>.from(
                              widget.model.componentOverrides[overrideKey],
                            )
                          : <String, dynamic>{};

                      existing['name'] = item.name;
                      existing['price'] = newPrice;
                      existing['calculated_price'] = newPrice;
                      existing['price_dzd'] = newPrice;
                      if (item.catalogItemId != null)
                        existing['id'] = item.catalogItemId;
                      if (item.profileCode != null)
                        existing['code'] = item.profileCode;

                      widget.model.componentOverrides[overrideKey] = existing;
                      // أيضاً نسجل بنفس الاسم الأصلي لضمان التقاط createProfile له
                      widget.model.componentOverrides[item.originalName] =
                          existing;

                      if (saveToDb) {
                        await _updatePriceInDatabase(item, newPrice);
                      }

                      if (mounted) {
                        setState(() {});
                        await _refreshVisibleBomItems();
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
    return meas
        .replaceAll('.', '')
        .replaceAll(',', ''); // إزالة النقطة والفاصلة لتوحيد صيغة المقارنة
  }
  return extractSizeDigits(component['name'].toString());
}

String? getComponentMeasurementKey(Map<String, dynamic> component) {
  final measurement = (component['measurement'] ?? '').toString().trim();
  final source = measurement.isNotEmpty
      ? measurement
      : (component['name'] ?? '').toString();
  final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(source);
  final value = match == null
      ? null
      : double.tryParse(match.group(0)!.replaceAll(',', '.'));
  if (value == null || value <= 0) return null;
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
}

String? getBladeTrackSize(Map<String, dynamic> blade) {
  final trackMeasurement = (blade['track_measurement'] ?? '').toString().trim();
  if (trackMeasurement.isEmpty) return getComponentMeasurementKey(blade);
  return getComponentMeasurementKey({
    'measurement': trackMeasurement,
    'name': blade['name'],
  });
}
