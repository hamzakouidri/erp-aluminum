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
import 'package:database_data/Commande/Systeme/parclose_cut_mode_selector.dart';
import 'package:database_data/Commande/window_painter.dart'; // رسّام يعرض شكل النافذة (Custom Painter)
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart'; // نافذة اختيار بروفيل/مكون بدي
import 'package:provider/provider.dart'; // لإدارة حالة الإعدادات العامة (اللغة...)
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart'; // دالة الترجمة حسب اللغة
import 'package:database_data/utils/color_name_localization.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/widgets/section_image.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // نوع Database لاستعلامات SQL المباشرة
import 'package:shared_preferences/shared_preferences.dart'; // تخزين إعدادات التسعير محليًا (نسبة الربح...)

part 'material_consumption/table.dart';
part 'material_consumption/pricing.dart';
part 'material_consumption/kits.dart';
part 'material_consumption/bom.dart';

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
  // The kit options depend only on the window height and selected blade
  // (see _shutterKitOptions).
  Future<List<Map<String, dynamic>>>? _shutterKitOptionsFuture;
  String? _shutterKitOptionsKey;
  /// [setState] for the topic extensions in `material_consumption/` (a
  /// protected member cannot be called from an extension without a lint).
  void _setScreenState(VoidCallback fn) => setState(fn);

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



  int? _itemColorId(BomItem item) {
    final isAccessory =
        item.category == 'accessory' || item.category == 'other';
    final selectedColor = isAccessory
        ? widget.model.selectedAccessoryColor
        : widget.model.selectedDbColor;
    final value = item.colorId ?? selectedColor?['id'];
    return value is num ? value.toInt() : int.tryParse('${value ?? ''}');
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


  double get _wImg => _columnWidth(_colImg, _defaultWImg);

  double get _wName => _columnWidth(_colName, _defaultWName);

  double get _wColor => _columnWidth(_colColor, _defaultWColor);

  double get _wLen => _columnWidth(_colLen, _defaultWLen);

  double get _wQty => _columnWidth(_colQty, _defaultWQty);

  double get _wActualMeters =>
      _columnWidth(_colActualMeters, _defaultWActualMeters);


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




















  bool _hasRepeatedForRestoredSeries = false;






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
              if (widget.model.catalogIssues.isNotEmpty)
                _buildCatalogIssuesWarning(lang),
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
                    // Isolate the drawing so table rebuilds/animations do not
                    // repaint the full window drawing on every frame.
                    child: RepaintBoundary(
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
