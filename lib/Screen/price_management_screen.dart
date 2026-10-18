import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:database_data/widgets/app_material.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import '../utils/real_color_resolver.dart';
import '../widgets/section_image.dart';
import '../widgets/price_sync_banner.dart';
import 'standard_sheets_screen.dart';

class GlassDisplayItem {
  final Map<String, dynamic> glass;
  final String? specificColor;
  final double price;

  GlassDisplayItem({
    required this.glass,
    this.specificColor,
    required this.price,
  });
}

class _PendingShutterPrice {
  final double price;
  final Future<void> Function(double price) save;

  const _PendingShutterPrice({required this.price, required this.save});
}

class PriceManagementScreen extends StatefulWidget {
  final int initialIndex;

  const PriceManagementScreen({super.key, this.initialIndex = 0});

  @override
  State<PriceManagementScreen> createState() => _PriceManagementScreenState();
}

class _PriceManagementScreenState extends State<PriceManagementScreen>
    with SingleTickerProviderStateMixin {
  final SqlDatabase db = SqlDatabase();

  bool get canChangePrices => Provider.of<AppSettingsProvider>(
    context,
    listen: false,
  ).canChangePrices();
  late TabController _tabController;

  List<Map<String, dynamic>> seriesList = [];
  List<Map<String, dynamic>> allColorList = [];
  List<Map<String, dynamic>> filteredColorListForSeries = [];
  List<Map<String, dynamic>> glassList = [];
  List<Map<String, dynamic>> shutterList = [];
  List<Map<String, dynamic>> accessoryList = [];
  List<Map<String, dynamic>> jointList = [];
  List<Map<String, dynamic>> sectionList = [];
  List<Map<String, dynamic>> profilesList = [];
  List<Map<String, dynamic>> shutterBoxLimitsList = [];
  List<Map<String, dynamic>> kitBundlesList = [];
  List<Map<String, dynamic>> caissonTunnelPricesList = [];
  List<Map<String, dynamic>> temperedGlassItemsList = [];
  String _temperedGlassSearchQuery = '';
  String _temperedGlassCategoryFilter = 'all';

  Map<int, Map<int, double>> seriesColorPrices = {};
  Map<int, Map<int, double>> sectionColorPrices = {};
  Map<int, Map<int, double>> accessoryColorPrices = {};
  Map<int, Map<int, double>> shutterColorPrices = {};
  Map<int, Map<String, double>> glassColorPrices = {};
  Map<String, Map<int, double>> shutterSqmPrices = {};
  Map<int, List<int>> profileColorsMap = {};
  Map<int, Map<String, dynamic>> profileCalculationRules = {};
  List<String> shutterLamesList = [];
  List<String> shutterGlissieresList = [];
  int _shutterPricingMode = 0; // 0: Components, 1: Square Meter Prices
  int _accessoryPricingMode =
      0; // 0: standard/color prices, 1: included in selling price
  String _shutterSearchQuery = '';
  String _accessorySearchQuery = '';
  final Map<String, _PendingShutterPrice> _pendingShutterPrices = {};
  bool _isSavingAllShutterPrices = false;
  String _jointSearchQuery = '';

  bool isLoading = true;
  int? selectedAccessoryId;
  int? selectedShutterId;
  int? selectedSeriesId;
  int? selectedProfileId;
  int? selectedSeriesForSections;

  StreamSubscription? _dbSubscription;
  Timer? _reloadDebounce;
  final PageStorageBucket _scrollStorage = PageStorageBucket();
  int _loadRequestId = 0;
  static const String _selectedTabStorageKey = 'price-management-selected-tab';
  static const String _shutterModeStorageKey = 'price-management-shutter-mode';
  static int? _sessionSelectedTab;
  static int? _sessionShutterMode;
  bool _restoredPageState = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 11,
      vsync: this,
      initialIndex: _sessionSelectedTab ?? widget.initialIndex,
    );
    _tabController.addListener(_persistSelectedTab);
    _loadAllData();
    _dbSubscription = CloudSyncService().dbUpdateStream.listen((event) {
      // Price lists must not rebuild for order, measurement, or generic
      // database events. Those events are frequent and were resetting the
      // scroll position while the user was entering a price.
      if (event != 'catalog_downloaded') {
        return;
      }
      _scheduleDataReload();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredPageState) return;
    _restoredPageState = true;

    final bucket = PageStorage.maybeOf(context);
    final savedTab = bucket?.readState(
      context,
      identifier: _selectedTabStorageKey,
    );
    final restoredTab = savedTab is int ? savedTab : _sessionSelectedTab;
    if (restoredTab != null &&
        restoredTab >= 0 &&
        restoredTab < _tabController.length) {
      _tabController.index = restoredTab;
      _sessionSelectedTab = restoredTab;
    }

    final savedShutterMode = bucket?.readState(
      context,
      identifier: _shutterModeStorageKey,
    );
    final restoredShutterMode = savedShutterMode is int
        ? savedShutterMode
        : _sessionShutterMode;
    if (restoredShutterMode != null &&
        restoredShutterMode >= 0 &&
        restoredShutterMode <= 1) {
      _shutterPricingMode = restoredShutterMode;
      _sessionShutterMode = restoredShutterMode;
    }
  }

  void _persistSelectedTab() {
    if (!_tabController.indexIsChanging) {
      _sessionSelectedTab = _tabController.index;
      PageStorage.maybeOf(context)?.writeState(
        context,
        _tabController.index,
        identifier: _selectedTabStorageKey,
      );
    }
  }

  void _setShutterPricingMode(int mode) {
    if (_shutterPricingMode == mode) return;
    setState(() => _shutterPricingMode = mode);
    _sessionShutterMode = mode;
    PageStorage.maybeOf(
      context,
    )?.writeState(context, mode, identifier: _shutterModeStorageKey);
  }

  /// A catalogue import can emit more than one catalogue event in a short
  /// time. Reload only once, without reacting to unrelated application data.
  void _scheduleDataReload() {
    if (!mounted) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _loadAllData();
    });
  }

  double _readStoredPrice(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0.0;
  }

  bool _isShutterGreyBaseColor(Map<String, dynamic> color) {
    final name = (color['name'] ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-]+'), '')
        .replaceAll('ى', 'ي');
    return const {'grey', 'gray', 'gris', 'رمادي'}.contains(name);
  }

  Map<String, dynamic> _shutterColorMapFor(int colorId) {
    return allColorList.firstWhere(
      (color) => color['id'] == colorId,
      orElse: () => {'id': colorId, 'name': 'Color $colorId'},
    );
  }

  Future<void> _loadAllData() async {
    // Ignore a slower, older reload if a more recent database event arrives
    // while it is still reading.  Otherwise its late setState can replace the
    // current list and reset the user's visible position.
    final requestId = ++_loadRequestId;
    await db.ensureShutterComponentsUseGreyPrice();
    await db.ensureProfileColorDefaults();
    await db.ensureProfileCalculationRulesTable();
    await db.seedDefaultProfileCalculationRules();
    final dbInstance = (await db.db)!;

    Future<List<Map<String, dynamic>>> safeQuery(String table) async {
      try {
        return await dbInstance.query(table);
      } catch (e) {
        print("Error loading $table: $e");
        // Robust fallback to create missing tables on the fly
        if (table == 'SeriesColorPrices') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS SeriesColorPrices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              series_id INTEGER NOT NULL,
              color_id INTEGER NOT NULL,
              price REAL NOT NULL DEFAULT 0.0,
              UNIQUE(series_id, color_id)
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'SectionColorPrices') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS SectionColorPrices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              section_id INTEGER NOT NULL,
              color_id INTEGER NOT NULL,
              price REAL NOT NULL DEFAULT 0.0,
              UNIQUE(section_id, color_id)
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Colors') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Colors (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              hex_code TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'Global',
              price REAL NOT NULL DEFAULT 0.0
            )
          ''');
          try {
            await dbInstance.execute(
              'ALTER TABLE Colors ADD COLUMN price REAL NOT NULL DEFAULT 0.0;',
            );
          } catch (e) {}
          return await dbInstance.query(table);
        } else if (table == 'Series') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Series (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              profile_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              price_per_meter REAL NOT NULL DEFAULT 0.0
            )
          ''');
          try {
            await dbInstance.execute(
              'ALTER TABLE Series ADD COLUMN price_per_meter REAL NOT NULL DEFAULT 0.0;',
            );
          } catch (e) {}
          return await dbInstance.query(table);
        } else if (table == 'Glass') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Glass (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              thickness REAL NOT NULL,
              price_per_sqm REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Shutters') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Shutters (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              color_id INTEGER,
              price_per_sqm REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Accessories') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Accessories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              price REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Joints') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Joints (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              thickness REAL NOT NULL,
              price_per_meter REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'ShutterSqmPrices') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS ShutterSqmPrices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              blade_type TEXT NOT NULL,
              color_id INTEGER NOT NULL,
              price_per_sqm REAL NOT NULL DEFAULT 0.0,
              UNIQUE(blade_type, color_id)
            )
          ''');
          return await dbInstance.query(table);
        }
        return [];
      }
    }

    List<Map<String, dynamic>> sList = [];
    try {
      sList = await dbInstance.rawQuery('''
        SELECT 
          s.id, 
          s.profile_id, 
          s.name, 
          s.type, 
          s.price_per_meter,
          p.name as profile_name
        FROM Series s
        LEFT JOIN Profile p ON s.profile_id = p.id
      ''');
    } catch (e) {
      sList = await safeQuery('Series');
    }
    final cList = await safeQuery('Colors');
    final gList = await safeQuery('Glass');
    final shList = await safeQuery('ShutterComponents');
    final aList = await safeQuery('Accessories');
    final jList = await safeQuery('Joints');
    final secList = await safeQuery('Sections');
    final pList = await safeQuery('Profile');
    List<Map<String, dynamic>> kbList = [];
    try {
      // Use the dedicated reader so the compatibility schema (including the
      // persisted aggregate price column) is guaranteed before loading.
      kbList = await db.readKitBundles();
    } catch (_) {}

    List<Map<String, dynamic>> ctPricesList = [];
    try {
      ctPricesList = await db.getCaissonTunnelPrices();
    } catch (_) {}

    List<Map<String, dynamic>> limitsList = [];

    try {
      limitsList = await db.readShutterBoxLimits();
    } catch (e) {
      print("Error loading shutter box limits: $e");
    }

    Map<int, Map<String, double>> tempGlassColorPrices = {};
    try {
      final gPricesData = await safeQuery('GlassColorPrices');
      for (var row in gPricesData) {
        int gId = row['glass_id'] as int;
        String cName = row['color_name'] as String;
        double p = _readStoredPrice(row['price']);
        if (!tempGlassColorPrices.containsKey(gId)) {
          tempGlassColorPrices[gId] = {};
        }
        tempGlassColorPrices[gId]![cName] = p;
      }
    } catch (_) {}

    Map<int, Map<int, double>> tempPrices = {};
    Map<int, Map<int, double>> tempAccPrices = {};
    try {
      final pricesData = await safeQuery('SeriesColorPrices');
      for (var row in pricesData) {
        int sId = row['series_id'] as int;
        int cId = row['color_id'] as int;
        double p = (row['price'] as num).toDouble();
        if (!tempPrices.containsKey(sId)) {
          tempPrices[sId] = {};
        }
        tempPrices[sId]![cId] = p;
      }
    } catch (e) {
      print("Error parsing SeriesColorPrices: $e");
    }

    try {
      final accPricesData = await safeQuery('AccessoryColorPrices');
      // Build set of valid color IDs for quick lookup
      final validColorIds = cList.map((c) => c['id'] as int).toSet();

      for (var row in accPricesData) {
        int aId = row['accessory_id'] as int;
        int cId = row['color_id'] as int;
        double p = (row['price'] as num).toDouble();

        if (!validColorIds.contains(cId)) {
          // Color no longer exists in Colors table → delete orphaned entry
          try {
            await dbInstance.delete(
              'AccessoryColorPrices',
              where: 'accessory_id = ? AND color_id = ?',
              whereArgs: [aId, cId],
            );
          } catch (_) {}
          continue; // Skip adding to tempAccPrices
        }

        if (!tempAccPrices.containsKey(aId)) {
          tempAccPrices[aId] = {};
        }
        tempAccPrices[aId]![cId] = p;
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error parsing AccessoryColorPrices: $e");
      }
    }

    Map<int, Map<int, double>> tempSecPrices = {};
    try {
      final secPricesData = await safeQuery('SectionColorPrices');
      for (var row in secPricesData) {
        int secId = row['section_id'] as int;
        int cId = row['color_id'] as int;
        double p = (row['price'] as num).toDouble();
        if (!tempSecPrices.containsKey(secId)) {
          tempSecPrices[secId] = {};
        }
        tempSecPrices[secId]![cId] = p;
      }
    } catch (e) {
      Text("Error parsing SectionColorPrices: $e");
    }

    Map<int, List<int>> tempProfColors = {};
    try {
      final pcData = await safeQuery('ProfileColors');
      for (var row in pcData) {
        int pId = row['profile_id'] as int;
        int cId = row['color_id'] as int;
        if (!tempProfColors.containsKey(pId)) {
          tempProfColors[pId] = [];
        }
        tempProfColors[pId]!.add(cId);
      }
    } catch (e) {
      print("Error parsing ProfileColors: $e");
    }

    Map<int, Map<int, double>> tempShutterPrices = {};
    try {
      final shData = await safeQuery('ShutterColorPrices');
      for (var row in shData) {
        int sId = row['shutter_component_id'] as int;
        int cId = row['color_id'] as int;
        double p = _readStoredPrice(row['price']);
        if (!tempShutterPrices.containsKey(sId)) {
          tempShutterPrices[sId] = {};
        }
        tempShutterPrices[sId]![cId] = p;
      }
    } catch (e) {}

    Map<String, Map<int, double>> tempShutterSqmPrices = {};
    try {
      final sqmPricesData = await safeQuery('ShutterSqmPrices');
      for (var row in sqmPricesData) {
        String blade = row['blade_type'] as String;
        int cId = row['color_id'] as int;
        double p = _readStoredPrice(row['price_per_sqm']);
        if (!tempShutterSqmPrices.containsKey(blade)) {
          tempShutterSqmPrices[blade] = {};
        }
        tempShutterSqmPrices[blade]![cId] = p;
      }
    } catch (e) {
      print("Error parsing ShutterSqmPrices: $e");
    }

    final tempProfileCalculationRules = <int, Map<String, dynamic>>{};
    try {
      final rules = await db.getProfileCalculationRules();
      for (final rule in rules) {
        final sectionId = (rule['section_id'] as num?)?.toInt();
        if (sectionId != null) {
          tempProfileCalculationRules[sectionId] = rule;
        }
      }
    } catch (_) {}

    List<String> tempLames = [];
    List<String> tempGlissieres = [];
    try {
      final opts = await db.getShutterOptions();
      tempLames = opts['lames'] ?? [];
      tempGlissieres = opts['glissieres'] ?? [];
    } catch (_) {}
    if (tempLames.isEmpty) {
      tempLames = ['Lame Injectée', 'Lame Extrudée'];
    }
    if (tempGlissieres.isEmpty) {
      tempGlissieres = ['Glissière 25', 'Glissière 120', 'Glissière 100'];
    }

    final tempTgItems = await db.getTemperedGlassItems();
    if (!mounted || requestId != _loadRequestId) return;
    setState(() {
      seriesList = sList;
      allColorList = cList;
      glassList = gList;
      shutterList = shList;
      accessoryList = aList;
      jointList = jList;
      sectionList = secList;
      profilesList = pList;
      shutterBoxLimitsList = limitsList;
      kitBundlesList = kbList;
      caissonTunnelPricesList = ctPricesList;
      temperedGlassItemsList = tempTgItems;

      seriesColorPrices = tempPrices;
      accessoryColorPrices = tempAccPrices;
      sectionColorPrices = tempSecPrices;
      shutterColorPrices = tempShutterPrices;
      shutterSqmPrices = tempShutterSqmPrices;
      shutterLamesList = tempLames;
      shutterGlissieresList = tempGlissieres;
      glassColorPrices = tempGlassColorPrices;
      profileColorsMap = tempProfColors;
      profileCalculationRules = tempProfileCalculationRules;

      if (seriesList.isNotEmpty) {
        if (selectedSeriesId == null ||
            !seriesList.any((s) => s['id'] == selectedSeriesId)) {
          selectedSeriesId = seriesList.first['id'] as int;
        }
        if (selectedSeriesForSections == null ||
            !seriesList.any((s) => s['id'] == selectedSeriesForSections)) {
          selectedSeriesForSections = seriesList.first['id'] as int;
        }
      } else {
        selectedSeriesId = null;
        selectedSeriesForSections = null;
      }
      if (profilesList.isNotEmpty) {
        if (selectedProfileId == null ||
            !profilesList.any((p) => p['id'] == selectedProfileId)) {
          selectedProfileId = profilesList.first['id'] as int;
        }
      } else {
        selectedProfileId = null;
      }
      if (accessoryList.isNotEmpty) {
        if (selectedAccessoryId == null ||
            !accessoryList.any((a) => a['id'] == selectedAccessoryId)) {
          selectedAccessoryId = accessoryList.first['id'] as int;
        }
      } else {
        selectedAccessoryId = null;
      }

      isLoading = false;
    });
    await _updateFilteredColors(requestId: requestId);
  }

  Future<void> _updateFilteredColors({int? requestId}) async {
    if (selectedSeriesId == null) return;
    final series = seriesList.firstWhere(
      (s) => s['id'] == selectedSeriesId,
      orElse: () => {},
    );
    if (series.isNotEmpty) {
      int profileId = series['profile_id'] as int;
      final filtered = await db.getColorsForProfile(profileId);
      if (mounted && (requestId == null || requestId == _loadRequestId)) {
        setState(() {
          filteredColorListForSeries = filtered;
        });
      }
    }
  }

  Widget _buildColorCircle(Map<String, dynamic> dbColor, {double size = 20}) {
    final woodImage = realColorTextureImage(dbColor);
    final parsedColor = realGradientColors(dbColor)[1];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: woodImage != null ? null : parsedColor,
        image: woodImage,
        border: Border.all(color: Colors.grey.shade400, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePrice(
    String table,
    int id,
    String column,
    double newPrice,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final dbInstance = (await db.db)!;
    await dbInstance.update(
      table,
      {column: newPrice},
      where: 'id = ?',
      whereArgs: [id],
    );
    // A base catalogue price typed by the manager is a workshop price: keep
    // it across catalogue refreshes and send it to the workshop's phones.
    if (SqlDatabase.workshopBasePriceColumns[table]?.contains(column) ??
        false) {
      await db.recordWorkshopPrice(
        dbInstance,
        table: table,
        rowKey: SqlDatabase.priceRowKey([id]),
        column: column,
        price: newPrice,
        source: 'manual',
      );
    }
    CloudSyncService().notifyChange();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
        backgroundColor: Colors.green,
      ),
    );
    _loadAllData();
  }

  void _queueShutterPrice({
    required String key,
    required double price,
    required double currentPrice,
    required Future<void> Function(double price) save,
  }) {
    if (!mounted) return;
    setState(() {
      if ((price - currentPrice).abs() < 0.000001) {
        _pendingShutterPrices.remove(key);
      } else {
        _pendingShutterPrices[key] = _PendingShutterPrice(
          price: price,
          save: save,
        );
      }
    });
  }

  void _removeQueuedShutterPrice(String key) {
    if (!mounted || !_pendingShutterPrices.containsKey(key)) return;
    setState(() => _pendingShutterPrices.remove(key));
  }

  Future<void> _saveAllShutterPrices() async {
    if (_isSavingAllShutterPrices || _pendingShutterPrices.isEmpty) return;

    final pending = Map<String, _PendingShutterPrice>.from(
      _pendingShutterPrices,
    );
    setState(() => _isSavingAllShutterPrices = true);

    final savedKeys = <String>[];
    var failedCount = 0;
    for (final entry in pending.entries) {
      try {
        await entry.value.save(entry.value.price);
        savedKeys.add(entry.key);
      } catch (_) {
        failedCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      for (final key in savedKeys) {
        _pendingShutterPrices.remove(key);
      }
      _isSavingAllShutterPrices = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failedCount == 0
              ? 'تم حفظ ${savedKeys.length} سعراً بنجاح.'
              : 'تم حفظ ${savedKeys.length} سعراً، وتعذر حفظ $failedCount.',
        ),
        backgroundColor: failedCount == 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _updateSeriesColorPrice(
    int seriesId,
    int colorId,
    double price,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    await db.setSeriesColorPrice(seriesId, colorId, price);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
    _loadAllData();
  }

  Widget _buildSeriesColorTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (seriesList.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لم يتم العثور على سلاسل. يرجى إضافة سلاسل أولاً.',
            lang,
          ),
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
        ),
      );
    }
    if (filteredColorListForSeries.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لم يتم العثور على ألوان. يرجى تخصيص الألوان لهذا البروفيل من شاشة الألوان أولاً.',
            lang,
          ),
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: [
        PriceSyncBanner(
          categoryKey: 'series',
          onPriceUpdated: _loadAllData,
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Select Series',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
            ),
            initialValue: selectedSeriesId,
            items: seriesList.map((s) {
              String displayName = s['name'].toString();
              if (s['profile_name'] != null) {
                displayName = "${s['profile_name']} - $displayName";
              }
              return DropdownMenuItem<int>(
                value: s['id'] as int,
                child: Text(
                  displayName,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedSeriesId = val;
              });
              _updateFilteredColors();
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey<String>('price-series-colors-list'),
            padding: EdgeInsets.all(16),
            itemCount: filteredColorListForSeries.length,
            itemBuilder: (context, index) {
              final color = filteredColorListForSeries[index];
              final cId = color['id'] as int;
              double currentPrice = 0.0;
              if (selectedSeriesId != null &&
                  seriesColorPrices.containsKey(selectedSeriesId)) {
                currentPrice = seriesColorPrices[selectedSeriesId]?[cId] ?? 0.0;
              }
              if (currentPrice == 0.0 && selectedSeriesId != null) {
                final s = seriesList.firstWhere(
                  (s) => s['id'] == selectedSeriesId,
                  orElse: () => {},
                );
                if (s.isNotEmpty) {
                  currentPrice =
                      (s['price_per_meter'] as num?)?.toDouble() ?? 0.0;
                }
              }

              return Container(
                margin: EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  border: Border.all(width: 1, color: Colors.grey.shade300),
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      spreadRadius: 2,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: PriceEditRow(
                  title: color['name'].toString(),
                  titleIcon: _buildColorCircle(color, size: 24),
                  subtitle: Localization.translate('سعر المتر الطولي', lang),
                  currentPrice: currentPrice,
                  canChangePrices: canChangePrices,
                  onSave: (parsed) {
                    if (selectedSeriesId != null) {
                      _updateSeriesColorPrice(selectedSeriesId!, cId, parsed);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _updateAccessoryColorPrice(
    int accId,
    int colorId,
    double price,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    await db.setAccessoryColorPrice(accId, colorId, price);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
    _loadAllData();
  }

  Widget _buildShutterPricingTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Column(
      children: [
        // Components and m² selling prices are separate price pages.
        PriceSyncBanner(
          key: ValueKey('shutter-sync-$_shutterPricingMode'),
          categoryKey: _shutterPricingMode == 0 ? 'shutters' : 'shutter_sqm',
          onPriceUpdated: _loadAllData,
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setShutterPricingMode(0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _shutterPricingMode == 0
                            ? Colors.deepPurple
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        Localization.translate('أسعار المكونات والقطع', lang),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _shutterPricingMode == 0
                              ? Colors.white
                              : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setShutterPricingMode(1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _shutterPricingMode == 1
                            ? Colors.deepPurple
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        Localization.translate('سعر المتر المربع للستار', lang),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _shutterPricingMode == 1
                              ? Colors.white
                              : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_shutterPricingMode == 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: Localization.translate(
                  'بحث في مكونات الستار...',
                  lang,
                ),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _shutterSearchQuery = val;
                });
              },
            ),
          ),
        if (_shutterPricingMode == 0 && canChangePrices)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _pendingShutterPrices.isEmpty
                        ? Localization.translate(
                            'لا توجد أسعار معدّلة بانتظار الحفظ.',
                            lang,
                          )
                        : '${_pendingShutterPrices.length} ${Localization.translate('أسعار جاهزة للحفظ.', lang)}',
                    style: TextStyle(
                      color: _pendingShutterPrices.isEmpty
                          ? Colors.grey.shade600
                          : Colors.deepPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed:
                      _pendingShutterPrices.isEmpty || _isSavingAllShutterPrices
                      ? null
                      : _saveAllShutterPrices,
                  icon: _isSavingAllShutterPrices
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _isSavingAllShutterPrices ? 'جارٍ الحفظ...' : 'حفظ الكل',
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _shutterPricingMode == 0
              ? _buildShutterComponentsList(context)
              : _buildShutterSqmPricesList(context),
        ),
      ],
    );
  }

  Widget _buildShutterComponentsList(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (shutterList.isEmpty && kitBundlesList.isEmpty) {
      return Center(
        child: Text(Localization.translate('لا توجد بيانات.', lang)),
      );
    }

    final query = _shutterSearchQuery.trim().toLowerCase();
    final filteredKits = kitBundlesList.where((kit) {
      if (query.isEmpty) return true;
      final name = (kit['name'] ?? '').toString().toLowerCase();
      final desc = (kit['description'] ?? '').toString().toLowerCase();
      return name.contains(query) || desc.contains(query);
    }).toList();

    final filteredShutters = shutterList.where((item) {
      if (query.isEmpty) return true;
      final name = (item['name'] ?? '').toString().toLowerCase();
      final code = (item['code'] ?? '').toString().toLowerCase();
      final type = (item['component_type'] ?? '').toString().toLowerCase();
      final subtype = (item['shutter_subtype'] ?? '').toString().toLowerCase();
      final measurement = (item['measurement'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          code.contains(query) ||
          type.contains(query) ||
          subtype.contains(query) ||
          measurement.contains(query);
    }).toList();

    final totalCount = filteredKits.length + filteredShutters.length;
    if (totalCount == 0) {
      return Center(
        child: Text(
          Localization.translate('لا توجد نتائج مطابقة للبحث.', lang),
        ),
      );
    }

    return ListView.builder(
      key: const PageStorageKey<String>('price-shutter-components-list'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index < filteredKits.length) {
          final kit = filteredKits[index];
          final kitId = kit['id'] as int;
          final kitName = kit['name'].toString();
          final currentPrice = _readStoredPrice(kit['price']);
          final pendingKey = 'kit-bundle-$kitId';

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.purple.shade600.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.08),
                  spreadRadius: 1,
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.purple,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kitName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.purple,
                              ),
                            ),
                            if ((kit['description'] ?? '')
                                .toString()
                                .isNotEmpty)
                              Text(
                                kit['description'].toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple.shade200),
                        ),
                        child: Text(
                          Localization.translate('حزمة كيت كاملة (Kit)', lang),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.purple.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.7),
                PriceEditRow(
                  key: ValueKey<String>('kit-bundle-price-$kitId'),
                  title: Localization.translate(
                    'السعر الإجمالي للكيت (دج)',
                    lang,
                  ),
                  titleIcon: const Icon(
                    Icons.sell_outlined,
                    color: Colors.purple,
                    size: 20,
                  ),
                  currentPrice: currentPrice,
                  canChangePrices: canChangePrices,
                  onSave: (parsed) => _updateKitBundlePrice(kitId, parsed),
                  onPriceChanged: (parsed) {
                    if (parsed == null) {
                      _removeQueuedShutterPrice(pendingKey);
                      return;
                    }
                    _queueShutterPrice(
                      key: pendingKey,
                      price: parsed,
                      currentPrice: currentPrice,
                      save: (price) => _updateKitBundlePrice(
                        kitId,
                        price,
                        showConfirmation: false,
                      ),
                    );
                  },
                  onSaveCompleted: () => _removeQueuedShutterPrice(pendingKey),
                ),
                const SizedBox(height: 4),
              ],
            ),
          );
        }

        final shutter = filteredShutters[index - filteredKits.length];
        final shutterId = shutter['id'] as int;
        final shutterName = shutter['name'].toString();

        final sColors = shutterColorPrices[shutterId] ?? {};
        final hasColorPrices = sColors.isNotEmpty;
        final colorIds = sColors.keys.toList()
          ..sort((left, right) {
            final leftIsGrey = _isShutterGreyBaseColor(
              _shutterColorMapFor(left),
            );
            final rightIsGrey = _isShutterGreyBaseColor(
              _shutterColorMapFor(right),
            );
            if (leftIsGrey == rightIsGrey) return left.compareTo(right);
            return leftIsGrey ? -1 : 1;
          });

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.deepPurple.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.08),
                spreadRadius: 1,
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.curtains, color: Colors.deepPurple, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        shutterName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                    // Badge: with colors or single price
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: hasColorPrices
                            ? Colors.deepPurple.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasColorPrices
                              ? Colors.deepPurple.shade200
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        hasColorPrices
                            ? Localization.translate('الألوان', lang)
                            : Localization.translate('خام', lang),
                        style: TextStyle(
                          fontSize: 11,
                          color: hasColorPrices
                              ? Colors.deepPurple
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.7),
              if (hasColorPrices) ...[
                ...colorIds.asMap().entries.map((entry) {
                  final colorIdx = entry.key;
                  final cId = entry.value;
                  final colorMap = _shutterColorMapFor(cId);
                  final cName = colorMap['name'].toString();
                  final isGreyBaseColor = _isShutterGreyBaseColor(colorMap);
                  final currentPrice = sColors[cId] ?? 0.0;
                  final pendingKey = 'shutter-color-$shutterId-$cId';

                  return Column(
                    children: [
                      PriceEditRow(
                        title: isGreyBaseColor
                            ? Localization.translate(
                                'رمادي (السعر الأساسي)',
                                lang,
                              )
                            : Localization.translate(cName, lang),
                        titleIcon: _buildColorCircle(colorMap, size: 24),
                        currentPrice: currentPrice,
                        canChangePrices: canChangePrices,
                        onSave: (parsed) =>
                            _updateShutterColorPrice(shutterId, cId, parsed),
                        onPriceChanged: (parsed) {
                          if (parsed == null) {
                            _removeQueuedShutterPrice(pendingKey);
                            return;
                          }
                          _queueShutterPrice(
                            key: pendingKey,
                            price: parsed,
                            currentPrice: currentPrice,
                            save: (price) => _updateShutterColorPrice(
                              shutterId,
                              cId,
                              price,
                              showConfirmation: false,
                            ),
                          );
                        },
                        onSaveCompleted: () =>
                            _removeQueuedShutterPrice(pendingKey),
                      ),
                      if (colorIdx < colorIds.length - 1)
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 16,
                          endIndent: 16,
                          color: Colors.grey.shade200,
                        ),
                    ],
                  );
                }),
              ] else ...[
                Builder(
                  builder: (context) {
                    final currentPrice = _readStoredPrice(shutter['price']);
                    final pendingKey = 'shutter-base-$shutterId';
                    return PriceEditRow(
                      title: Localization.translate('السعر (قطعة)', lang),
                      titleIcon: const Icon(
                        Icons.sell_outlined,
                        color: Colors.deepPurple,
                        size: 20,
                      ),
                      currentPrice: currentPrice,
                      canChangePrices: canChangePrices,
                      onSave: (parsed) =>
                          _updateShutterComponentBasePrice(shutterId, parsed),
                      onPriceChanged: (parsed) {
                        if (parsed == null) {
                          _removeQueuedShutterPrice(pendingKey);
                          return;
                        }
                        _queueShutterPrice(
                          key: pendingKey,
                          price: parsed,
                          currentPrice: currentPrice,
                          save: (price) => _updateShutterComponentBasePrice(
                            shutterId,
                            price,
                            showConfirmation: false,
                          ),
                        );
                      },
                      onSaveCompleted: () =>
                          _removeQueuedShutterPrice(pendingKey),
                    );
                  },
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTemperedGlassPricingTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;

    final filtered = temperedGlassItemsList.where((item) {
      final matchesCat =
          _temperedGlassCategoryFilter == 'all' ||
          item['category'] == _temperedGlassCategoryFilter;
      final q = _temperedGlassSearchQuery.trim().toLowerCase();
      final matchesQuery =
          q.isEmpty ||
          (item['name'] ?? '').toString().toLowerCase().contains(q) ||
          (item['notes'] ?? '').toString().toLowerCase().contains(q) ||
          (item['category_name'] ?? '').toString().toLowerCase().contains(q);
      return matchesCat && matchesQuery;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: switch (lang) {
                      AppLanguage.french =>
                        'Rechercher un accessoire / profilé verre trempé...',
                      AppLanguage.english =>
                        'Search tempered glass accessory / profile...',
                      _ => 'بحث في إكسسوارات وقطاعات الزجاج المقسى...',
                    },
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) =>
                      setState(() => _temperedGlassSearchQuery = val),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children:
                [
                  'all',
                  'poignee',
                  'charniere',
                  'profile',
                  'fixation',
                  'joint',
                  'serrure',
                ].map((cat) {
                  final isSel = _temperedGlassCategoryFilter == cat;
                  final catLabel = switch (cat) {
                    'all' => Localization.translate('الكل', lang),
                    'poignee' => switch (lang) {
                      AppLanguage.french => 'Poignées',
                      AppLanguage.english => 'Handles',
                      _ => 'المقابض',
                    },
                    'charniere' => switch (lang) {
                      AppLanguage.french => 'Charnières',
                      AppLanguage.english => 'Hinges',
                      _ => 'المفصلات',
                    },
                    'profile' => switch (lang) {
                      AppLanguage.french => 'Profilés & Rails',
                      AppLanguage.english => 'Profiles & Rails',
                      _ => 'القطاعات والسكك',
                    },
                    'fixation' => switch (lang) {
                      AppLanguage.french => 'Fixations',
                      AppLanguage.english => 'Clamps',
                      _ => 'التثبيت والمشابك',
                    },
                    'joint' => switch (lang) {
                      AppLanguage.french => 'Joints',
                      AppLanguage.english => 'Seals',
                      _ => 'الجوانات والعوازل',
                    },
                    'serrure' => switch (lang) {
                      AppLanguage.french => 'Serrures',
                      AppLanguage.english => 'Locks',
                      _ => 'الأقفال',
                    },
                    _ => cat,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 6, left: 6),
                    child: ChoiceChip(
                      selected: isSel,
                      label: Text(catLabel),
                      selectedColor: Colors.teal.shade600,
                      labelStyle: TextStyle(color: isSel ? Colors.white : null),
                      onSelected: (_) =>
                          setState(() => _temperedGlassCategoryFilter = cat),
                    ),
                  );
                }).toList(),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    Localization.translate('لم يتم العثور على عناصر.', lang),
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final name = item['name']?.toString() ?? '';
                    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                    final unit = item['unit']?.toString() ?? 'piece';
                    final unitLabel = unit == 'meter'
                        ? (lang == AppLanguage.french
                              ? '/m'
                              : (lang == AppLanguage.english ? '/m' : 'للمتر'))
                        : (lang == AppLanguage.french
                              ? '/pièce'
                              : (lang == AppLanguage.english
                                    ? '/pc'
                                    : 'للقطعة'));
                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Colors.teal.shade200.withValues(alpha: 0.5),
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade50,
                          child: Icon(
                            Icons.hardware_outlined,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${item['category_name'] ?? item['category'] ?? ''} • $unitLabel',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        trailing: SizedBox(
                          width: 170,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${price.toStringAsFixed(0)} DZD',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: Localization.translate(
                                  'تعديل السعر',
                                  lang,
                                ),
                                onPressed: () =>
                                    _showEditTemperedGlassPriceDialog(item),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showEditTemperedGlassPriceDialog(
    Map<String, dynamic> item,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final priceCtrl = TextEditingController(
      text: (item['price'] as num?)?.toString() ?? '0',
    );
    final costCtrl = TextEditingController(
      text: (item['cost_price'] as num?)?.toString() ?? '0',
    );
    final id = item['id'] as int;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(item['name']?.toString() ?? ''),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: switch (lang) {
                  AppLanguage.french => 'Prix de vente (DZD)',
                  AppLanguage.english => 'Selling Price (DZD)',
                  _ => 'سعر البيع (د.ج)',
                },
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: costCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: switch (lang) {
                  AppLanguage.french => 'Prix de revient / coût (DZD)',
                  AppLanguage.english => 'Cost Price (DZD)',
                  _ => 'سعر التكلفة (د.ج)',
                },
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Localization.translate('حفظ', lang)),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final p = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
      final c = double.tryParse(costCtrl.text.trim()) ?? 0.0;
      await db.updateTemperedGlassItem(id, {'price': p, 'cost_price': c});
      final dbInstance = await db.db;
      if (dbInstance != null) {
        for (final entry in {'price': p, 'cost_price': c}.entries) {
          await db.recordWorkshopPrice(
            dbInstance,
            table: 'TemperedGlassItems',
            rowKey: SqlDatabase.priceRowKey([id]),
            column: entry.key,
            price: entry.value,
            source: 'manual',
          );
        }
      }
      _loadAllData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildShutterSqmPricesList(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;

    // ── colour constants ──────────────────────────────────────────────────
    const Color lamePurple = Color(0xFF7C3AED);
    const Color coulisseBlue = Color(0xFF1D4ED8);
    const Color moteurOrange = Color(0xFFD97706);
    const Color manivelleGreen = Color(0xFF059669);

    // ── helper: section card ──────────────────────────────────────────────
    Widget sectionCard({
      required String title,
      required IconData icon,
      required Color color,
      required Widget body,
      Widget? trailing,
    }) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.07),
              spreadRadius: 1,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: color,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.8),
            body,
          ],
        ),
      );
    }

    // ── helper: color rows + add-button for a blade key ──────────────────
    Widget colorPriceSection({
      required String bladeKey,
      required Color accentColor,
      required String subtitle,
    }) {
      final colorMap = shutterSqmPrices[bladeKey] ?? {};
      final assignedColorIds = colorMap.keys.toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Existing color rows
          ...assignedColorIds.asMap().entries.map((entry) {
            final idx = entry.key;
            final cId = entry.value;
            final colMap = allColorList.firstWhere(
              (c) => c['id'] == cId,
              orElse: () => {
                'id': cId,
                'name': 'Color $cId',
                'hex_code': '#9E9E9E',
              },
            );
            double currentPrice = colorMap[cId] ?? 0.0;
            if (currentPrice == 0.0) {
              final comp = shutterList.firstWhere(
                (c) => c['name'] == bladeKey,
                orElse: () => {},
              );
              if (comp.isNotEmpty) {
                currentPrice = _readStoredPrice(comp['price']);
              }
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: PriceEditRow(
                          title: colMap['name'].toString(),
                          titleIcon: _buildColorCircle(colMap, size: 22),
                          subtitle: subtitle,
                          currentPrice: currentPrice,
                          canChangePrices: canChangePrices,
                          onSave: (parsed) {
                            _updateShutterSqmPrice(bladeKey, cId, parsed);
                          },
                        ),
                      ),
                      // Delete button
                      if (canChangePrices)
                        IconButton(
                          tooltip: Localization.translate('حذف', lang),
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red.shade300,
                            size: 20,
                          ),
                          onPressed: () async {
                            await db.deleteShutterSqmPrice(bladeKey, cId);
                            _loadAllData();
                          },
                        ),
                    ],
                  ),
                ),
                if (idx < assignedColorIds.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 16,
                    endIndent: 16,
                    color: Colors.grey.shade200,
                  ),
              ],
            );
          }),

          // Empty state
          if (assignedColorIds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Center(
                child: Text(
                  Localization.translate(
                    'لم تُضف ألوان بعد. اضغط + لإضافة لون.',
                    lang,
                  ),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Add color button
          if (canChangePrices) ...[
            const Divider(height: 1, thickness: 0.5),
            TextButton.icon(
              onPressed: () => _showAddSqmColorDialog(bladeKey, accentColor),
              icon: Icon(
                Icons.add_circle_outline,
                size: 18,
                color: accentColor,
              ),
              label: Text(
                Localization.translate('+ إضافة لون', lang),
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      );
    }

    // ── Lames section ─────────────────────────────────────────────────────
    // Show a sub-section per blade type (Injectée, Extrudée …)
    final List<Widget> lameSubSections = [];
    for (int i = 0; i < shutterLamesList.length; i++) {
      final blade = shutterLamesList[i];
      lameSubSections.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 0.8,
                color: Color(0xFFE9D5FF),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                blade,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: lamePurple,
                ),
              ),
            ),
            colorPriceSection(
              bladeKey: blade,
              accentColor: lamePurple,
              subtitle: Localization.translate('سعر م²', lang),
            ),
          ],
        ),
      );
    }

    // ── Caisson Tunnel section ───────────────────────────────────────────
    final caissonDbNames = shutterList
        .where((item) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          final type = (item['component_type'] ?? '').toString().toLowerCase();
          return type == 'caisson_tunnel' || name.contains('caisson');
        })
        .map((item) => (item['name'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toSet();

    final List<String> caissonTypesList = caissonDbNames.isNotEmpty
        ? caissonDbNames.toList()
        : [
            'Caisson Tunnel 25 cm',
            'Caisson Tunnel 30 cm',
            'Caisson Tunnel 40 cm',
          ];

    final List<Widget> caissonSubSections = [];
    const Color caissonOrange = Colors.deepOrange;
    for (int i = 0; i < caissonTypesList.length; i++) {
      final caissonName = caissonTypesList[i];

      caissonSubSections.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 0.8,
                color: Color(0xFFFFCC80),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.view_in_ar_rounded,
                    size: 16,
                    color: caissonOrange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    caissonName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: caissonOrange,
                    ),
                  ),
                ],
              ),
            ),
            colorPriceSection(
              bladeKey: caissonName,
              accentColor: caissonOrange,
              subtitle: Localization.translate('سعر المتر الخطي', lang),
            ),
          ],
        ),
      );
    }

    // ── Moteur installation fee ───────────────────────────────────────────
    final double moteurInstallPrice =
        (shutterSqmPrices['Moteur_Install']?[0]) ?? 0.0;

    // ── Manivelle price ───────────────────────────────────────────────────
    final double manivellePrice = (shutterSqmPrices['Manivelle']?[0]) ?? 0.0;

    // ── Special Accessories Prices ────────────────────────────────────────
    final double obInstallPrice = (shutterSqmPrices['OB_Install']?[0]) ?? 0.0;
    final double demiOBInstallPrice =
        (shutterSqmPrices['DemiOB_Install']?[0]) ?? 0.0;
    final double verrouInstallPrice =
        (shutterSqmPrices['Verrou_Install']?[0]) ?? 0.0;
    final double moustiquaireSqmPrice =
        (shutterSqmPrices['Moustiquaire_Sqm']?[0]) ?? 0.0;

    return ListView(
      key: const PageStorageKey<String>('price-shutter-sqm-list'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        sectionCard(
          title: 'الموستيكير (Moustiquaire) — سعر المتر المربع',
          icon: Icons.grid_on_rounded,
          color: Colors.green,
          body: PriceEditRow(
            title: 'السعر الرسمي للمتر المربع',
            titleIcon: const Icon(
              Icons.square_foot_rounded,
              size: 18,
              color: Colors.green,
            ),
            subtitle: 'يُطبق تلقائياً عند إضافتها إلى النافذة',
            currentPrice: moustiquaireSqmPrice,
            canChangePrices: canChangePrices,
            onSave: (parsed) =>
                _updateShutterSqmPrice('Moustiquaire_Sqm', 0, parsed),
          ),
        ),

        // ── 1. Lames ──────────────────────────────────────────────────────
        sectionCard(
          title: Localization.translate(
            'الشرائح (Lames) — سعر المتر المربع',
            lang,
          ),
          icon: Icons.curtains_closed,
          color: lamePurple,
          body: lameSubSections.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    Localization.translate(
                      'لا توجد أنواع لام. أضف من إعدادات الستار.',
                      lang,
                    ),
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : Column(children: lameSubSections),
        ),

        // ── 1.5 Caisson Tunnel ─────────────────────────────────────────────
        sectionCard(
          title: Localization.translate(
            'Caisson Tunnel — سعر المتر الخطي',
            lang,
          ),
          icon: Icons.view_in_ar_rounded,
          color: caissonOrange,
          body: caissonSubSections.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    Localization.translate(
                      'لا توجد أنواع Caisson Tunnel في قاعدة البيانات.',
                      lang,
                    ),
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : Column(children: caissonSubSections),
        ),

        // ── 2. Coulisses (by type, not color) ─────────────────────────────
        sectionCard(
          title: Localization.translate(
            'السكك (Coulisses) — سعر لكل نوع',
            lang,
          ),
          icon: Icons.linear_scale,
          color: coulisseBlue,
          body: shutterGlissieresList.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    Localization.translate(
                      'لا توجد أنواع سكك. أضف من إعدادات الستار.',
                      lang,
                    ),
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : Column(
                  children: shutterGlissieresList.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final railName = entry.value;
                    // Store in ShutterSqmPrices as blade_type=railName, color_id=0
                    final currentPrice =
                        (shutterSqmPrices[railName]?[0]) ?? 0.0;

                    return Column(
                      children: [
                        PriceEditRow(
                          title: railName,
                          titleIcon: Icon(
                            Icons.linear_scale,
                            size: 18,
                            color: coulisseBlue,
                          ),
                          subtitle: Localization.translate('سعر الوحدة', lang),
                          currentPrice: currentPrice,
                          canChangePrices: canChangePrices,
                          onSave: (parsed) {
                            _updateShutterSqmPrice(railName, 0, parsed);
                          },
                        ),
                        if (idx < shutterGlissieresList.length - 1)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 16,
                            endIndent: 16,
                            color: Colors.grey.shade200,
                          ),
                      ],
                    );
                  }).toList(),
                ),
        ),

        // ── 3. Moteur ─────────────────────────────────────────────────────
        sectionCard(
          title: Localization.translate('المحرك (Moteur) — سعر التركيب', lang),
          icon: Icons.settings_input_component_outlined,
          color: moteurOrange,
          body: Column(
            children: [
              // Info chip
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: moteurOrange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: moteurOrange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: moteurOrange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          Localization.translate(
                            'سعر المحرك يُحسب تلقائياً من المنتج المختار في قاعدة البيانات. أضف هنا فقط سعر التركيب الإضافي.',
                            lang,
                          ),
                          style: TextStyle(fontSize: 11, color: moteurOrange),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PriceEditRow(
                title: Localization.translate('سعر التركيب', lang),
                titleIcon: Icon(
                  Icons.build_outlined,
                  size: 18,
                  color: moteurOrange,
                ),
                subtitle: Localization.translate('يُضاف إلى سعر المحرك', lang),
                currentPrice: moteurInstallPrice,
                canChangePrices: canChangePrices,
                onSave: (parsed) {
                  _updateShutterSqmPrice('Moteur_Install', 0, parsed);
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),

        // ── 4. Manivelle ──────────────────────────────────────────────────
        sectionCard(
          title: Localization.translate('المانيفال (Manivelle)', lang),
          icon: Icons.rotate_right,
          color: manivelleGreen,
          body: Column(
            children: [
              PriceEditRow(
                title: Localization.translate('سعر تركيب المانيفال', lang),
                titleIcon: Icon(
                  Icons.rotate_right,
                  size: 18,
                  color: manivelleGreen,
                ),
                subtitle: Localization.translate('يُضاف إلى سعر القطعة', lang),
                currentPrice: manivellePrice,
                canChangePrices: canChangePrices,
                onSave: (parsed) {
                  _updateShutterSqmPrice('Manivelle', 0, parsed);
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),

        // ── 5. Special Accessories ───────────────────────────────────────
        sectionCard(
          title: Localization.translate('إكسسوارات خاصة', lang),
          icon: Icons.extension,
          color: Colors.blueGrey,
          body: Column(
            children: [
              PriceEditRow(
                title: Localization.translate('سعر الكيت OB', lang),
                titleIcon: const Icon(
                  Icons.build_circle_outlined,
                  size: 18,
                  color: Colors.blueGrey,
                ),
                currentPrice: obInstallPrice,
                canChangePrices: canChangePrices,
                onSave: (parsed) =>
                    _updateShutterSqmPrice('OB_Install', 0, parsed),
              ),
              const SizedBox(height: 4),
              PriceEditRow(
                title: Localization.translate('سعر ديمي OB', lang),
                titleIcon: const Icon(
                  Icons.build_circle_outlined,
                  size: 18,
                  color: Colors.blueGrey,
                ),
                currentPrice: demiOBInstallPrice,
                canChangePrices: canChangePrices,
                onSave: (parsed) =>
                    _updateShutterSqmPrice('DemiOB_Install', 0, parsed),
              ),
              const SizedBox(height: 4),
              PriceEditRow(
                title: Localization.translate('سعر الفيرو سنترال', lang),
                titleIcon: const Icon(
                  Icons.build_circle_outlined,
                  size: 18,
                  color: Colors.blueGrey,
                ),
                currentPrice: verrouInstallPrice,
                canChangePrices: canChangePrices,
                onSave: (parsed) =>
                    _updateShutterSqmPrice('Verrou_Install', 0, parsed),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  /// Dialog to pick any color freely and assign it to a blade_type in ShutterSqmPrices
  Future<void> _showAddSqmColorDialog(
    String bladeKey,
    Color accentColor,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final alreadyAdded = shutterSqmPrices[bladeKey]?.keys.toSet() ?? {};

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final available = allColorList
                .where((c) => !alreadyAdded.contains(c['id'] as int))
                .toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.palette_outlined, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${Localization.translate('اختر لوناً لـ', lang)} ${Localization.translate(bladeKey, lang)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: available.isEmpty
                    ? Center(
                        child: Text(
                          Localization.translate(
                            'كل الألوان المتاحة مضافة بالفعل.',
                            lang,
                          ),
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: available.length,
                        itemBuilder: (_, i) {
                          final color = available[i];
                          final cId = color['id'] as int;
                          return ListTile(
                            leading: _buildColorCircle(color, size: 28),
                            title: Text(color['name'].toString()),
                            trailing: Icon(
                              Icons.add_circle_outline,
                              color: accentColor,
                            ),
                            onTap: () async {
                              // Add with price = 0 so user can fill it in the list
                              await db.insertOrUpdateShutterSqmPrice(
                                bladeKey,
                                cId,
                                0.0,
                              );
                              await _loadAllData();
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إغلاق', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateShutterSqmPrice(
    String bladeType,
    int colorId,
    double price,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    await db.insertOrUpdateShutterSqmPrice(bladeType, colorId, price);
    _loadAllData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
        ),
      );
    }
  }

  Future<void> _updateShutterComponentBasePrice(
    int shutterId,
    double price, {
    bool showConfirmation = true,
  }) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final dbInstance = await db.db;
    if (dbInstance == null) return;
    await dbInstance.update(
      'ShutterComponents',
      {'price': price},
      where: 'id = ?',
      whereArgs: [shutterId],
    );
    await db.recordWorkshopPrice(
      dbInstance,
      table: 'ShutterComponents',
      rowKey: SqlDatabase.priceRowKey([shutterId]),
      column: 'price',
      price: price,
      source: 'manual',
    );
    CloudSyncService().notifyChange();
    if (!mounted) return;
    setState(() {
      final idx = shutterList.indexWhere((item) => item['id'] == shutterId);
      if (idx != -1) {
        final mutable = Map<String, dynamic>.from(shutterList[idx]);
        mutable['price'] = price;
        shutterList[idx] = mutable;
      }
    });
    if (showConfirmation && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
    _loadAllData();
  }

  Future<void> _updateKitBundlePrice(
    int kitId,
    double price, {
    bool showConfirmation = true,
  }) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    await db.updateKitBundlePrice(kitId, price);
    final dbInstance = await db.db;
    if (dbInstance != null) {
      final kitRow = kitBundlesList.firstWhere(
        (k) => k['id'] == kitId,
        orElse: () => {},
      );
      final kitName = kitRow['name']?.toString();
      if (kitName != null && kitName.isNotEmpty) {
        await dbInstance.update(
          'ShutterComponents',
          {'price': price},
          where:
              "LOWER(TRIM(name)) = LOWER(TRIM(?)) AND LOWER(TRIM(component_type)) = 'kit'",
          whereArgs: [kitName],
        );
      }
    }
    if (!mounted) return;
    setState(() {
      final idx = kitBundlesList.indexWhere((k) => k['id'] == kitId);
      if (idx != -1) {
        final mutable = Map<String, dynamic>.from(kitBundlesList[idx]);
        mutable['price'] = price;
        kitBundlesList[idx] = mutable;
      }
    });
    if (showConfirmation && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
    // The in-memory row above is already the source for this widget. Reloading
    // the complete screen while PriceEditRow is still awaiting its save callback
    // can unmount Provider dependants mid-callback (`_dependents.isEmpty`). The
    // database-change subscription will perform any later external refresh.
  }

  Future<void> _updateShutterColorPrice(
    int shutterId,
    int colorId,
    double price, {
    bool showConfirmation = true,
  }) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    await db.setShutterColorForComponent(
      shutterComponentId: shutterId,
      colorId: colorId,
      enabled: true,
      price: price,
    );
    if (!mounted) return;
    setState(() {
      shutterColorPrices.putIfAbsent(shutterId, () => {})[colorId] = price;
    });
    if (showConfirmation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildAccessoryColorTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: isDark ? Border.all(color: Colors.grey.shade800) : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _accessoryPricingMode = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _accessoryPricingMode == 0
                            ? Colors.deepPurple
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        Localization.translate('أسعار الإكسسوارات', lang),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _accessoryPricingMode == 0
                              ? Colors.white
                              : (isDark ? Colors.grey.shade300 : Colors.black),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _accessoryPricingMode = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _accessoryPricingMode == 1
                            ? Colors.deepPurple
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        Localization.translate(
                          'الإكسسوارات المحتسبة في البيع',
                          lang,
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _accessoryPricingMode == 1
                              ? Colors.white
                              : (isDark ? Colors.grey.shade300 : Colors.black),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: Localization.translate('بحث في الإكسسوارات...', lang),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
            ),
            onChanged: (value) {
              setState(() => _accessorySearchQuery = value);
            },
          ),
        ),
        Expanded(
          child: _accessoryPricingMode == 0
              ? _buildAccessoryListStandard(context)
              : _buildAccessorySellingCalculationList(context),
        ),
      ],
    );
  }

  Widget _buildAccessoryListStandard(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (accessoryList.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لم يتم العثور على أكسسوارات.', lang),
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
          ),
        ),
      );
    }

    final query = _accessorySearchQuery.trim().toLowerCase();
    final filteredAccessories = accessoryList.where((accessory) {
      if (query.isEmpty) return true;
      final name = (accessory['name'] ?? '').toString().toLowerCase();
      final code = (accessory['code'] ?? '').toString().toLowerCase();
      final type = (accessory['type'] ?? '').toString().toLowerCase();
      final material = (accessory['material_type'] ?? '')
          .toString()
          .toLowerCase();
      return name.contains(query) ||
          code.contains(query) ||
          type.contains(query) ||
          material.contains(query);
    }).toList();

    if (filteredAccessories.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لا توجد نتائج مطابقة للبحث.', lang),
        ),
      );
    }

    filteredAccessories.sort((a, b) {
      final categoryOrder = _accessoryCategoryPriority(
        a,
      ).compareTo(_accessoryCategoryPriority(b));
      if (categoryOrder != 0) return categoryOrder;
      final category = _accessoryCategoryLabel(
        a,
      ).compareTo(_accessoryCategoryLabel(b));
      if (category != 0) return category;
      return (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      );
    });

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final accessory in filteredAccessories) {
      grouped
          .putIfAbsent(_accessoryCategoryLabel(accessory), () => [])
          .add(accessory);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 760;
        final children = <Widget>[];
        for (final group in grouped.entries) {
          children.add(
            _buildAccessoryCategoryHeader(group.key, group.value.length),
          );
          for (final accessory in group.value) {
            children.add(
              isDesktop
                  ? _buildDesktopAccessoryPriceCard(accessory, lang, isDark)
                  : _buildMobileAccessoryPriceTile(accessory, lang, isDark),
            );
          }
          children.add(const SizedBox(height: 12));
        }
        return ListView(
          key: const PageStorageKey<String>('price-accessories-standard-list'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: children,
        );
      },
    );
  }

  String _accessorySearchText(Map<String, dynamic> accessory) {
    return '${accessory['type'] ?? ''} ${accessory['name'] ?? ''}'
        .toLowerCase();
  }

  String _accessoryCategoryLabel(Map<String, dynamic> accessory) {
    final text = _accessorySearchText(accessory);
    if (text.contains('handle') ||
        text.contains('poign') ||
        text.contains('مقبض')) {
      return 'المقابض';
    }
    if (text.contains('hinge') ||
        text.contains('paum') ||
        text.contains('مفصل')) {
      return 'المفاصل';
    }
    if (text.contains('lock') ||
        text.contains('serrure') ||
        text.contains('verrou') ||
        text.contains('قفل') ||
        text.contains('فيرو')) {
      return 'الأقفال والإغلاقات';
    }
    if (text.contains('roul') ||
        text.contains('wheel') ||
        text.contains('عجل')) {
      return 'العجلات';
    }
    if (text.contains('gache') ||
        text.contains('gâche') ||
        text.contains('قاش')) {
      return 'القاشات';
    }
    if (text.contains('cremone') ||
        text.contains('crémone') ||
        text.contains('كريمون')) {
      return 'الكريمونات';
    }
    if (text.contains('bouchon') || text.contains('بوشون')) {
      return 'الأغطية والبوشونات';
    }
    final rawType = (accessory['type'] ?? '').toString().trim();
    return rawType.isEmpty ? 'إكسسوارات أخرى' : rawType;
  }

  int _accessoryCategoryPriority(Map<String, dynamic> accessory) {
    switch (_accessoryCategoryLabel(accessory)) {
      case 'المقابض':
        return 0;
      case 'المفاصل':
        return 1;
      case 'الأقفال والإغلاقات':
        return 2;
      case 'العجلات':
        return 3;
      case 'القاشات':
        return 4;
      case 'الكريمونات':
        return 5;
      case 'الأغطية والبوشونات':
        return 6;
      default:
        return 20;
    }
  }

  Widget _buildAccessoryCategoryHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          const Icon(Icons.folder_copy_outlined, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              Localization.translate(
                label,
                Provider.of<AppSettingsProvider>(
                  context,
                  listen: false,
                ).language,
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Chip(label: Text('$count')),
        ],
      ),
    );
  }

  Widget _buildDesktopAccessoryPriceCard(
    Map<String, dynamic> accessory,
    AppLanguage lang,
    bool isDark,
  ) {
    final accessoryId = accessory['id'] as int;
    final name = (accessory['name'] ?? '').toString();
    final colors = accessoryColorPrices[accessoryId] ?? {};
    final basePrice = _readStoredPrice(accessory['price']);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: isDark ? const Color(0xFF1E1E1E) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${accessory['code'] ?? ''}${(accessory['code'] ?? '').toString().isNotEmpty ? ' • ' : ''}${accessory['type'] ?? ''}',
            ),
            trailing: IconButton(
              tooltip: Localization.translate('تخصيص الألوان', lang),
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => _showCustomizeAccessoryColorsDialog(
                initialAccId: accessoryId,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.isEmpty
                  ? [
                      _buildDesktopAccessoryPriceBox(
                        label: Localization.translate('خام', lang),
                        icon: Icon(
                          Icons.sell_outlined,
                          color: Colors.amber.shade700,
                        ),
                        price: basePrice,
                        onSave: (price) => _updatePrice(
                          'Accessories',
                          accessoryId,
                          'price',
                          price,
                        ),
                      ),
                    ]
                  : colors.entries.map((entry) {
                      final color = allColorList.firstWhere(
                        (item) => item['id'] == entry.key,
                        orElse: () => {'name': 'Color ${entry.key}'},
                      );
                      return _buildDesktopAccessoryPriceBox(
                        label: (color['name'] ?? '').toString(),
                        icon: _buildColorCircle(color, size: 24),
                        price: entry.value,
                        onSave: (price) => _updateAccessoryColorPrice(
                          accessoryId,
                          entry.key,
                          price,
                        ),
                      );
                    }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopAccessoryPriceBox({
    required String label,
    required Widget icon,
    required double price,
    required ValueChanged<double> onSave,
  }) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return SizedBox(
      width: 320,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            PriceEditRow(
              title: Localization.translate('السعر', lang),
              currentPrice: price,
              canChangePrices: canChangePrices,
              onSave: onSave,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileAccessoryPriceTile(
    Map<String, dynamic> accessory,
    AppLanguage lang,
    bool isDark,
  ) {
    final id = accessory['id'] as int;
    final colorCount = (accessoryColorPrices[id] ?? {}).length;
    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : null,
      child: ListTile(
        leading: const Icon(Icons.category_outlined),
        title: Text(
          (accessory['name'] ?? '').toString(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          colorCount == 0 ? 'سعر خام' : '$colorCount أسعار حسب اللون',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showAccessoryPriceEditor(accessory, lang),
      ),
    );
  }

  Future<void> _showAccessoryPriceEditor(
    Map<String, dynamic> accessory,
    AppLanguage lang,
  ) async {
    final id = accessory['id'] as int;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = accessoryColorPrices[id] ?? {};
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      (accessory['name'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(_accessoryCategoryLabel(accessory)),
                    trailing: IconButton(
                      icon: const Icon(Icons.palette_outlined),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showCustomizeAccessoryColorsDialog(initialAccId: id);
                      },
                    ),
                  ),
                  const Divider(),
                  if (colors.isEmpty)
                    PriceEditRow(
                      title: Localization.translate('خام', lang),
                      currentPrice: _readStoredPrice(accessory['price']),
                      canChangePrices: canChangePrices,
                      onSave: (price) =>
                          _updatePrice('Accessories', id, 'price', price),
                    )
                  else
                    ...colors.entries.map((entry) {
                      final color = allColorList.firstWhere(
                        (item) => item['id'] == entry.key,
                        orElse: () => {'name': 'Color ${entry.key}'},
                      );
                      return PriceEditRow(
                        title: (color['name'] ?? '').toString(),
                        titleIcon: _buildColorCircle(color, size: 24),
                        currentPrice: entry.value,
                        canChangePrices: canChangePrices,
                        onSave: (price) =>
                            _updateAccessoryColorPrice(id, entry.key, price),
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccessorySellingCalculationList(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final query = _accessorySearchQuery.trim().toLowerCase();
    // Filter out OB/Demi/Verrou accessory items, then apply the search.
    final filteredAccessories = accessoryList.where((acc) {
      final name = acc['name'].toString().toLowerCase();
      final code = (acc['code'] ?? '').toString().toLowerCase();
      final type = (acc['type'] ?? '').toString().toLowerCase();
      final material = (acc['material_type'] ?? '').toString().toLowerCase();

      if (name.contains('ob') || type.contains('ob')) return false;
      if (name.contains('demi') || type.contains('demi')) return false;
      if (name.contains('verrou') || type.contains('verrou')) return false;

      return query.isEmpty ||
          name.contains(query) ||
          code.contains(query) ||
          type.contains(query) ||
          material.contains(query);
    }).toList();

    final filteredKits = kitBundlesList.where((kit) {
      if (query.isEmpty) return true;
      final name = (kit['name'] ?? '').toString().toLowerCase();
      final description = (kit['description'] ?? '').toString().toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();

    final totalItemsCount = filteredKits.length + filteredAccessories.length;

    if (totalItemsCount == 0) {
      return Center(
        child: Text(
          Localization.translate('لم يتم العثور على أكسسوارات.', lang),
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.black87,
          ),
        ),
      );
    }

    return ListView.builder(
      key: const PageStorageKey<String>('price-accessories-calculated-list'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: totalItemsCount,
      itemBuilder: (context, index) {
        if (index < filteredKits.length) {
          final kit = filteredKits[index];
          final kitId = kit['id'] as int;
          final kitName = kit['name'].toString();
          final isCalculated = kit['is_selling_calculated'] != 0;

          return Card(
            color: isDark ? const Color(0xFF2D1F47) : Colors.deepPurple.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: isDark
                    ? Colors.purple.shade700
                    : Colors.deepPurple.shade100,
                width: 1,
              ),
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: SwitchListTile(
              title: Text(
                kitName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.purple.shade200 : Colors.deepPurple,
                ),
              ),
              subtitle: Text(
                kit['description']?.toString() ?? 'حزمة إكسسوارات كاملة',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
              value: isCalculated,
              activeColor: Colors.deepPurple,
              onChanged: canChangePrices
                  ? (val) {
                      _updateKitBundleSellingCalculation(kitId, val);
                    }
                  : null,
            ),
          );
        } else {
          final acc = filteredAccessories[index - filteredKits.length];
          final accId = acc['id'] as int;
          final accName = acc['name'].toString();
          final isCalculated = acc['is_selling_calculated'] == 1;

          return Card(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                width: 1,
              ),
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: SwitchListTile(
              title: Text(
                accName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Text(
                '${acc['type']} (${acc['material_type']})',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              value: isCalculated,
              activeColor: Colors.deepPurple,
              onChanged: canChangePrices
                  ? (val) {
                      _updateAccessorySellingCalculation(accId, val);
                    }
                  : null,
            ),
          );
        }
      },
    );
  }

  Future<void> _updateKitBundleSellingCalculation(
    int kitId,
    bool isChecked,
  ) async {
    final dbInstance = await db.db;
    await dbInstance!.update(
      'KitBundles',
      {'is_selling_calculated': isChecked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [kitId],
    );
    _loadAllData();
  }

  Future<void> _updateAccessorySellingCalculation(
    int accId,
    bool isChecked,
  ) async {
    final dbInstance = await db.db;
    await dbInstance!.update(
      'Accessories',
      {'is_selling_calculated': isChecked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [accId],
    );
    _loadAllData();
  }

  Future<void> _updateSectionColorPrice(
    int sectionId,
    int colorId,
    double price,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    try {
      await db.setSectionColorPrice(sectionId, colorId, price);
      if (!mounted) return;
      setState(() {
        sectionColorPrices.putIfAbsent(sectionId, () => {})[colorId] = price;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
      await _loadAllData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${Localization.translate('تعذر حفظ سعر القطاع', lang)}: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleProfileColor(
    int profileId,
    int colorId,
    bool isSelected,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await db.setColorForProfile(
        profileId: profileId,
        colorId: colorId,
        enabled: isSelected,
      );
      final savedColors = await db.getColorsForProfile(profileId);
      final saved = savedColors.any(
        (color) => color['id']?.toString() == colorId.toString(),
      );
      if (saved != isSelected) {
        throw StateError('لم يتم تأكيد حفظ تخصيص اللون.');
      }
      await _loadAllData();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم حفظ تخصيص اللون.', lang)),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${Localization.translate('تعذر حفظ تخصيص اللون', lang)}: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProfileColorsTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (profilesList.isEmpty) {
      return Center(
        child: Text(Localization.translate('لا يوجد أنظمة (Profiles).', lang)),
      );
    }
    if (allColorList.isEmpty) {
      return Center(
        child: Text(Localization.translate('لا توجد ألوان.', lang)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: Localization.translate('اختر النظام (Profile)', lang),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
            ),
            initialValue: selectedProfileId,
            items: profilesList.map((p) {
              return DropdownMenuItem<int>(
                value: p['id'] as int,
                child: Text(
                  p['name'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedProfileId = val;
              });
            },
          ),
        ),

        Expanded(
          child: Builder(
            builder: (context) {
              if (selectedProfileId == null) {
                return Center(
                  child: Text(
                    Localization.translate(
                      'الرجاء اختيار نظام لرؤية ألوانه.',
                      lang,
                    ),
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                );
              }

              final profileColors = allColorList.where((color) {
                final cId = color['id'] as int;
                if (profileColorsMap.containsKey(selectedProfileId)) {
                  return profileColorsMap[selectedProfileId]!.contains(cId);
                }
                return false;
              }).toList();

              if (profileColors.isEmpty) {
                return Center(
                  child: Text(
                    Localization.translate(
                      'لا توجد ألوان مرتبطة بهذا النظام.',
                      lang,
                    ),
                  ),
                );
              }

              return ListView.builder(
                key: const PageStorageKey<String>('price-profile-colors-list'),
                padding: EdgeInsets.all(16),
                itemCount: profileColors.length,
                itemBuilder: (context, index) {
                  final color = profileColors[index];

                  return Card(
                    elevation: 3,
                    margin: EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: _buildColorCircle(color, size: 30),
                      title: Text(
                        color['name'].toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      trailing: Icon(
                        Icons.palette,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showEditBarLengthDialog(Map<String, dynamic> section) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final ctrl = TextEditingController(
      text: section['bar_length']?.toString() ?? '6.0',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${Localization.translate('تعديل طول البار', lang)} - ${section['name']}',
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: Localization.translate('طول البار (بالمتر)', lang),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newLength = double.tryParse(ctrl.text) ?? 6.0;
              final dbInstance = (await db.db)!;
              await dbInstance.update(
                'Sections',
                {'bar_length': newLength},
                where: 'id = ?',
                whereArgs: [section['id']],
              );
              CloudSyncService().notifyChange();
              if (mounted) {
                Navigator.pop(ctx);
                _loadAllData();
              }
            },
            child: Text(Localization.translate('حفظ', lang)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionPricingTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).cardColor,
            child: TabBar(
              tabs: [
                Tab(text: Localization.translate('أسعار البروفيلات', lang)),
                Tab(
                  text: Localization.translate('قواعد حساب البروفيلات', lang),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSectionPricesList(context),
                _buildProfileCalculationRulesList(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionPricesList(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (seriesList.isEmpty) {
      return Center(
        child: Text(Localization.translate('لا توجد سلاسل.', lang)),
      );
    }

    final rawFilteredSections = sectionList
        .where((s) => s['series_id'] == selectedSeriesForSections)
        .toList();

    // Filter out duplicates by code (case-insensitive) and name (case-insensitive) to prevent database duplicates
    final seenSections = <String>{};
    final filteredSections = <Map<String, dynamic>>[];
    for (var s in rawFilteredSections) {
      final code = s['code']?.toString().toLowerCase().trim() ?? '';
      final name = s['name']?.toString().toLowerCase().trim() ?? '';
      final key = '$code|$name';
      if (key.isNotEmpty && !seenSections.contains(key)) {
        seenSections.add(key);
        filteredSections.add(s);
      }
    }

    // Find profile_id for selected series to know which colors to show
    int? currentProfileId;
    if (selectedSeriesForSections != null) {
      final s = seriesList.firstWhere(
        (s) => s['id'] == selectedSeriesForSections,
        orElse: () => {},
      );
      if (s.isNotEmpty) currentProfileId = s['profile_id'] as int?;
    }

    List<int> availableColors = [];
    if (currentProfileId != null &&
        profileColorsMap.containsKey(currentProfileId)) {
      availableColors = profileColorsMap[currentProfileId]!;
    }

    final validColors = allColorList
        .where((c) => availableColors.contains(c['id'] as int))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: Localization.translate('اختر السلسلة', lang),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
            ),
            initialValue: selectedSeriesForSections,
            items: seriesList.map((s) {
              String displayName = s['name'].toString();
              if (s['profile_name'] != null) {
                displayName = "${s['profile_name']} - $displayName";
              }
              return DropdownMenuItem<int>(
                value: s['id'] as int,
                child: Text(
                  displayName,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedSeriesForSections = val;
              });
            },
          ),
        ),
        if (validColors.isEmpty && selectedSeriesForSections != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              Localization.translate(
                "يرجى تحديد ألوان النظام أولاً من تبويب 'ألوان الأنظمة'.",
                lang,
              ),
              style: TextStyle(color: Colors.red),
            ),
          ),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey<String>('price-sections-list'),
            padding: EdgeInsets.all(16),
            itemCount: filteredSections.length,
            itemBuilder: (context, index) {
              final section = filteredSections[index];
              final secId = section['id'] as int;

              return Card(
                margin: EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 2,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => _showSectionImage(section),
                            child: Container(
                              width: MediaQuery.sizeOf(context).width < 600
                                  ? 72
                                  : 92,
                              height: MediaQuery.sizeOf(context).width < 600
                                  ? 72
                                  : 92,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: SectionImageWidget(
                                code: section['code']?.toString(),
                                name: section['name']?.toString(),
                                imagePath: section['image_path']?.toString(),
                                size: MediaQuery.sizeOf(context).width < 600
                                    ? 60
                                    : 80,
                                fallbackIcon: Icons.view_in_ar_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  section['name'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${Localization.translate('الرمز', lang)}: ${section['code']}",
                                ),
                                if (section['type'] != null)
                                  Text(
                                    section['type'].toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (canChangePrices)
                            IconButton(
                              tooltip: Localization.translate('تعديل', lang),
                              icon: const Icon(Icons.edit, color: Colors.grey),
                              onPressed: () =>
                                  _showEditBarLengthDialog(section),
                            ),
                        ],
                      ),
                      SizedBox(height: 10),
                      if (validColors.isNotEmpty)
                        ...validColors.map((color) {
                          final cId = color['id'] as int;
                          double currentPrice = 0.0;
                          if (sectionColorPrices.containsKey(secId)) {
                            currentPrice =
                                sectionColorPrices[secId]?[cId] ?? 0.0;
                          }
                          if (currentPrice == 0.0) {
                            currentPrice =
                                (section['price_per_meter'] as num?)
                                    ?.toDouble() ??
                                0.0;
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: PriceEditRow(
                              title: color['name'].toString(),
                              currentPrice: currentPrice,
                              canChangePrices: canChangePrices,
                              onSave: (parsed) =>
                                  _updateSectionColorPrice(secId, cId, parsed),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showSectionImage(Map<String, dynamic> section) async {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final imageSize = screenWidth < 600 ? screenWidth - 96 : 360.0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${section['code'] ?? ''} - ${section['name'] ?? ''}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: SizedBox.square(
          dimension: imageSize.clamp(180.0, 360.0).toDouble(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SectionImageWidget(
                code: section['code']?.toString(),
                name: section['name']?.toString(),
                imagePath: section['image_path']?.toString(),
                size: imageSize.clamp(160.0, 336.0).toDouble(),
                fallbackIcon: Icons.view_in_ar_rounded,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editProfileLinearMultiplier(
    int sectionId,
    double currentMultiplier,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    var inputValue = currentMultiplier.toStringAsFixed(
      currentMultiplier == currentMultiplier.roundToDouble() ? 0 : 2,
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Localization.translate('معامل المتر الخطي', lang)),
        content: TextFormField(
          initialValue: inputValue,
          onChanged: (value) => inputValue = value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: Localization.translate('مثال: 1 أو 2 للبلانت', lang),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(inputValue.trim());
              if (parsed != null && parsed.isFinite && parsed > 0) {
                Navigator.pop(dialogContext, parsed);
              }
            },
            child: Text(Localization.translate('حفظ', lang)),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    await db.saveProfileCalculationRule(
      sectionId: sectionId,
      calculationMode:
          profileCalculationRules[sectionId]?['calculation_mode']?.toString() ??
          'auto',
      linearMeterMultiplier: value,
      excludeFromPricing:
          profileCalculationRules[sectionId]?['exclude_from_pricing'] == 1 ||
          profileCalculationRules[sectionId]?['exclude_from_pricing'] == true,
    );
    if (!mounted) return;
    setState(() {
      profileCalculationRules[sectionId] = {
        ...?profileCalculationRules[sectionId],
        'section_id': sectionId,
        'calculation_mode':
            profileCalculationRules[sectionId]?['calculation_mode'] ?? 'auto',
        'linear_meter_multiplier': value,
      };
    });
  }

  Future<void> _setProfileCalculationMode(
    int sectionId,
    String mode,
    double multiplier,
  ) async {
    final exclude = mode == 'excluded';
    await db.saveProfileCalculationRule(
      sectionId: sectionId,
      calculationMode: exclude ? 'auto' : mode,
      linearMeterMultiplier: multiplier,
      excludeFromPricing: exclude,
    );
    if (!mounted) return;
    setState(() {
      profileCalculationRules[sectionId] = {
        ...?profileCalculationRules[sectionId],
        'section_id': sectionId,
        'calculation_mode': exclude ? 'auto' : mode,
        'exclude_from_pricing': exclude ? 1 : 0,
        'linear_meter_multiplier': multiplier,
      };
    });
  }

  Widget _buildProfileCalculationRulesList(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (seriesList.isEmpty) {
      return Center(
        child: Text(Localization.translate('لا توجد سلاسل.', lang)),
      );
    }
    final sections = sectionList
        .where((s) => s['series_id'] == selectedSeriesForSections)
        .toList();
    if (sections.isEmpty) {
      return Center(
        child: Text(Localization.translate('لا توجد بروفيلات.', lang)),
      );
    }
    bool isRuleActive(Map<String, dynamic> section) {
      final sectionId = (section['id'] as num).toInt();
      final rule = profileCalculationRules[sectionId];
      return rule?['exclude_from_pricing'] != 1 &&
          rule?['exclude_from_pricing'] != true;
    }

    final activeSections = sections.where(isRuleActive).toList(growable: false);
    final inactiveSections = sections
        .where((section) => !isRuleActive(section))
        .toList(growable: false);
    final orderedSections = [...activeSections, ...inactiveSections];

    String statusTitle(bool active) => switch (lang) {
      AppLanguage.arabic => active ? 'القواعد النشطة' : 'القواعد غير النشطة',
      AppLanguage.french => active ? 'Règles actives' : 'Règles inactives',
      AppLanguage.english => active ? 'Active rules' : 'Inactive rules',
    };

    Widget statusDivider(bool active, int count) {
      final colors = Theme.of(context).colorScheme;
      final color = active ? colors.primary : colors.outline;
      return Container(
        margin: const EdgeInsets.only(bottom: 10, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: active
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
              color: color,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                statusTitle(active),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: selectedSeriesForSections,
            decoration: InputDecoration(
              labelText: Localization.translate('اختر السلسلة', lang),
              border: const OutlineInputBorder(),
            ),
            items: seriesList.map((s) {
              final name = s['profile_name'] == null
                  ? '${s['name']}'
                  : '${s['profile_name']} - ${s['name']}';
              return DropdownMenuItem<int>(
                value: s['id'] as int,
                child: Text(name, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => selectedSeriesForSections = value);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            Localization.translate(
              'الافتراضي: المتر الخطي للإطار والظلفة والباتمو والتقسيمات فقط. باقي البروفيلات بسعرها الأساسي، والزجاج والبانو والإكسسوارات بأسعارها الخاصة.',
              lang,
            ),
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount:
                orderedSections.length +
                (activeSections.isNotEmpty ? 1 : 0) +
                (inactiveSections.isNotEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              if (activeSections.isNotEmpty) {
                if (index == 0) {
                  return statusDivider(true, activeSections.length);
                }
                index--;
              }
              if (index < activeSections.length) {
                // Continue below with the active section at this index.
              } else {
                index -= activeSections.length;
                if (inactiveSections.isNotEmpty && index == 0) {
                  return statusDivider(false, inactiveSections.length);
                }
                if (inactiveSections.isNotEmpty) index--;
                index += activeSections.length;
              }
              final section = orderedSections[index];
              final sectionId = (section['id'] as num).toInt();
              final rule = profileCalculationRules[sectionId];
              final storedMode =
                  rule?['calculation_mode']?.toString() ?? 'auto';
              final mode =
                  (rule?['exclude_from_pricing'] == 1 ||
                      rule?['exclude_from_pricing'] == true)
                  ? 'excluded'
                  : const {
                      'auto',
                      'linear_meter',
                      'base_price',
                    }.contains(storedMode)
                  ? storedMode
                  : 'auto';
              final multiplier =
                  (rule?['linear_meter_multiplier'] as num?)?.toDouble() ?? 1.0;
              return Card(
                key: ValueKey<String>('profile-calculation-rule-$sectionId'),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${section['name']}  (${section['code'] ?? ''})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey<String>(
                                'profile-calculation-mode-$sectionId-$mode',
                              ),
                              isExpanded: true,
                              initialValue: mode == 'auto' ? null : mode,
                              decoration: InputDecoration(
                                labelText: Localization.translate(
                                  'طريقة الحساب',
                                  lang,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'excluded',
                                  child: Text(
                                    Localization.translate(
                                      'لا يُحتسب بدون سعر',
                                      lang,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'linear_meter',
                                  child: Text(
                                    Localization.translate('متر خطي', lang),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'base_price',
                                  child: Text(
                                    Localization.translate('سعر أساسي', lang),
                                  ),
                                ),
                              ],
                              onChanged: canChangePrices
                                  ? (value) {
                                      if (value != null) {
                                        _setProfileCalculationMode(
                                          sectionId,
                                          value,
                                          multiplier,
                                        );
                                      }
                                    }
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 112,
                            child: OutlinedButton(
                              onPressed: canChangePrices
                                  ? () => _editProfileLinearMultiplier(
                                      sectionId,
                                      multiplier,
                                    )
                                  : null,
                              child: Text('× ${multiplier.toStringAsFixed(2)}'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGlassList(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (glassList.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لا توجد عناصر. يرجى إضافتها من قائمة المنتجات أولاً.',
            lang,
          ),
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Expand Glass list to individual items per color for Panneau, Baguette and Rosette types
    List<GlassDisplayItem> displayItems = [];
    for (var g in glassList) {
      final typeLower = g['type'].toString().toLowerCase();
      final hasColors =
          typeLower == 'panneau' ||
          typeLower == 'baguette' ||
          typeLower == 'rosette';
      if (hasColors) {
        final colorsStr = g['color']?.toString() ?? '';
        if (colorsStr.isNotEmpty) {
          final colorsList = colorsStr.split(',');
          for (var col in colorsList) {
            final trimmedCol = col.trim();
            if (trimmedCol.isEmpty) continue;
            final specificPrice =
                glassColorPrices[g['id']]?[trimmedCol] ??
                (g['price_per_sqm'] as num?)?.toDouble() ??
                0.0;
            displayItems.add(
              GlassDisplayItem(
                glass: g,
                specificColor: trimmedCol,
                price: specificPrice,
              ),
            );
          }
        } else {
          displayItems.add(
            GlassDisplayItem(
              glass: g,
              price: (g['price_per_sqm'] as num?)?.toDouble() ?? 0.0,
            ),
          );
        }
      } else {
        displayItems.add(
          GlassDisplayItem(
            glass: g,
            price: (g['price_per_sqm'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      }
    }

    if (displayItems.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لا توجد عناصر. يرجى إضافتها من قائمة المنتجات أولاً.',
            lang,
          ),
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      key: const PageStorageKey<String>('price-glass-list'),
      padding: const EdgeInsets.all(16),
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final item = displayItems[index];
        final String name = item.glass['name']?.toString() ?? '';
        final String glassType = item.glass['type']?.toString() ?? '';
        final String subtype = item.glass['subtype']?.toString() ?? '';
        final normalizedSubtype = subtype.toLowerCase();
        final isDecorPanneau =
            glassType.toLowerCase() == 'panneau' &&
            (normalizedSubtype.contains('decor') ||
                normalizedSubtype.contains('décor') ||
                normalizedSubtype.contains('ديكور'));
        final int id = item.glass['id'] as int;

        String displayTitle = name;
        if (item.specificColor != null) {
          displayTitle =
              '$name  —  ${Localization.translate('اللون: ', lang)}'
              '${Localization.translate(item.specificColor!, lang)}';
        } else {
          final String colorText = item.glass['color']?.toString() ?? '';
          if (colorText.isNotEmpty) {
            displayTitle =
                '$name  —  ${Localization.translate('اللون: ', lang)}'
                '${Localization.translate(colorText, lang)}';
          }
        }

        String displaySubtitle = Localization.translate(
          'سعر المتر المربع',
          lang,
        );
        if (glassType.isNotEmpty) {
          final t = glassType.toLowerCase();
          if (t == 'baguette') {
            displaySubtitle =
                '${Localization.translate('سعر المتر الخطي', lang)}  |  '
                '${Localization.translate('النوع: ', lang)}'
                '${Localization.translate('باجيت ديكور', lang)}';
          } else if (t == 'rosette') {
            displaySubtitle =
                '${Localization.translate('سعر القطعة', lang)}  |  '
                '${Localization.translate('النوع: ', lang)}'
                '${Localization.translate('وردة ديكور', lang)}';
          } else if (isDecorPanneau) {
            displaySubtitle =
                '${Localization.translate('سعر القطعة', lang)}  |  '
                '${Localization.translate('النوع: ', lang)}'
                '${Localization.translate('بانو ديكور', lang)}';
          } else {
            displaySubtitle =
                '${Localization.translate('سعر المتر المربع', lang)}  |  '
                '${Localization.translate('النوع: ', lang)}'
                '${Localization.translate(glassType, lang)}';
            if (t == 'panneau' && subtype.isNotEmpty) {
              displaySubtitle += ' (${Localization.translate(subtype, lang)})';
            }
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          decoration: BoxDecoration(
            border: Border.all(width: 1, color: Colors.grey.shade300),
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: PriceEditRow(
            title: displayTitle,
            subtitle: displaySubtitle,
            currentPrice: item.price,
            canChangePrices: canChangePrices,
            onSave: (parsed) async {
              if (item.specificColor != null) {
                await db.setGlassColorPrice(id, item.specificColor!, parsed);
                _loadAllData();
              } else {
                _updatePrice('Glass', id, 'price_per_sqm', parsed);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    List<Map<String, dynamic>> list,
    String tableName,
    String nameCol,
    String priceCol,
    String subtitle,
  ) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (list.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لا توجد عناصر. يرجى إضافتها من قائمة المنتجات أولاً.',
            lang,
          ),
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    final query = _jointSearchQuery.trim().toLowerCase();
    final filtered = list.where((item) {
      if (query.isEmpty) return true;
      final name = (item[nameCol] ?? '').toString().toLowerCase();
      return name.contains(query);
    }).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: Localization.translate('بحث...', lang),
              prefixIcon: Icon(
                Icons.search,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              isDense: true,
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF1E1E1E)
                  : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _jointSearchQuery = val;
              });
            },
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    Localization.translate('لا توجد نتائج مطابقة للبحث.', lang),
                    style: TextStyle(
                      color: isDark ? Colors.grey.shade400 : Colors.grey,
                    ),
                  ),
                )
              : ListView.builder(
                  key: PageStorageKey<String>(
                    'price-${tableName.toLowerCase()}-list',
                  ),
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final currentPrice = (item[priceCol] is num)
                        ? (item[priceCol] as num).toDouble()
                        : 0.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 1,
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade300,
                        ),
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.25)
                                : Colors.grey.withValues(alpha: 0.1),
                            spreadRadius: 2,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: PriceEditRow(
                        title: item[nameCol].toString(),
                        subtitle: subtitle,
                        currentPrice: currentPrice,
                        canChangePrices: canChangePrices,
                        onSave: (parsed) {
                          _updatePrice(tableName, item['id'], priceCol, parsed);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShutterBoxLimitsTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditShutterBoxLimitDialog(null),
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: shutterBoxLimitsList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.crop_square_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Localization.translate(
                      'لا توجد حدود مسجلة للصناديق.',
                      lang,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditShutterBoxLimitDialog(null),
                    icon: const Icon(Icons.add),
                    label: Text(
                      Localization.translate('إضافة قاعدة جديدة', lang),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              key: const PageStorageKey<String>('price-shutter-limits-list'),
              padding: const EdgeInsets.all(12),
              itemCount: shutterBoxLimitsList.length,
              itemBuilder: (context, index) {
                final limit = shutterBoxLimitsList[index];
                final id = limit['id'] as int;
                final boxSize = limit['box_size'] as int;
                final maxHeight =
                    (limit['max_height'] as num?)?.toDouble() ?? 0;
                final maxWidth =
                    (limit['blade_max_width'] as num?)?.toDouble() ?? 6000;
                final bladeName =
                    limit['blade_name']?.toString() ?? 'شفرة غير معروفة';

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: isDark ? 0.4 : 0.25),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.25)
                            : Colors.grey.withValues(alpha: 0.08),
                        spreadRadius: 1,
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      child: Icon(Icons.settings_overscan, color: Colors.white),
                    ),
                    title: Text(
                      bladeName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E3A5F)
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${Localization.translate('الصندوق:', lang)} $boxSize ${Localization.translate('ملم', lang)}',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.blue.shade200
                                    : Colors.blue.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1B4332)
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${Localization.translate('أقصى عرض اللامة:', lang)} ${maxWidth.toStringAsFixed(0)} ${Localization.translate('ملم', lang)}',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.green.shade200
                                    : Colors.green.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF3E2723)
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${Localization.translate('أقصى ارتفاع:', lang)} ${maxHeight.toStringAsFixed(0)} ${Localization.translate('ملم', lang)}',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.orange.shade200
                                    : Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () =>
                              _showAddEditShutterBoxLimitDialog(limit),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _confirmDeleteShutterBoxLimit(id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Caisson Tunnel Pricing Tab
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildCaissonTunnelPricingTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    const Color caissonColor = Color(0xFFE65100); // deep orange

    // Get all Caisson Tunnel items from database (shutterList)
    final caissonDbNames = shutterList
        .where((item) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          final type = (item['component_type'] ?? '').toString().toLowerCase();
          return type == 'caisson_tunnel' || name.contains('caisson');
        })
        .map((item) => (item['name'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toSet();

    final List<String> caissonTypesList = caissonDbNames.isNotEmpty
        ? caissonDbNames.toList()
        : [
            'Caisson Tunnel 25 cm',
            'Caisson Tunnel 30 cm',
            'Caisson Tunnel 40 cm',
          ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  caissonColor.withValues(alpha: 0.12),
                  caissonColor.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: caissonColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: caissonColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.view_in_ar_rounded,
                    color: caissonColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Caisson Tunnel — Prix au mètre linéaire',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Saisissez le prix au mètre linéaire (DA/ml) pour chaque type de Caisson Tunnel.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const PageStorageKey<String>('price-caisson-tunnel-list'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: caissonTypesList.length,
              itemBuilder: (context, index) {
                final caissonName = caissonTypesList[index];

                double currentPrice =
                    (shutterSqmPrices[caissonName]?[0]) ?? 0.0;
                if (currentPrice == 0.0) {
                  final comp = shutterList.firstWhere(
                    (c) => c['name'] == caissonName,
                    orElse: () => {},
                  );
                  if (comp.isNotEmpty) {
                    currentPrice = (comp['price'] as num?)?.toDouble() ?? 0.0;
                  }
                }

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: caissonColor.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: PriceEditRow(
                    title: caissonName,
                    titleIcon: const Icon(
                      Icons.view_in_ar_rounded,
                      size: 20,
                      color: caissonColor,
                    ),
                    subtitle: Localization.translate(
                      'سعر المتر الخطي (DA/ml)',
                      lang,
                    ),
                    currentPrice: currentPrice,
                    canChangePrices: canChangePrices,
                    onSave: (parsed) {
                      _updateShutterSqmPrice(caissonName, 0, parsed);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteShutterBoxLimit(int id) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Localization.translate('حذف القاعدة', lang)),
        content: Text(
          Localization.translate(
            'هل أنت متأكد من رغبتك في حذف هذه القاعدة؟',
            lang,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(Localization.translate('حذف', lang)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await db.deleteShutterBoxLimit(id);
      _loadAllData();
    }
  }

  Future<void> _showAddEditShutterBoxLimitDialog(
    Map<String, dynamic>? existingLimit,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    // Filter blades
    final blades = shutterList.where((s) {
      final name = s['name'].toString().toLowerCase();
      return (name.contains('lame') || name.contains('شريح')) &&
          !name.contains('final') &&
          !name.contains('نهائي') &&
          !name.contains('box') &&
          !name.contains('صندوق') &&
          !name.contains('caisson') &&
          !name.contains('kit') &&
          !name.contains('كيت');
    }).toList();

    if (blades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              'الرجاء إضافة شفرات في قائمة الستائر أولاً.',
              lang,
            ),
          ),
        ),
      );
      return;
    }

    int? selectedBladeId = existingLimit != null
        ? existingLimit['blade_id'] as int
        : blades.first['id'] as int;
    int selectedBoxSize = existingLimit != null
        ? existingLimit['box_size'] as int
        : 155;
    final heightCtrl = TextEditingController(
      text: existingLimit != null
          ? ((existingLimit['max_height'] as num?)?.toDouble() ?? 0)
                .toStringAsFixed(0)
          : '1800',
    );
    final widthCtrl = TextEditingController(
      text: existingLimit != null
          ? ((existingLimit['blade_max_width'] as num?)?.toDouble() ?? 6000)
                .toStringAsFixed(0)
          : '6000',
    );

    final boxSizes = [155, 185, 205];

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                existingLimit == null
                    ? Localization.translate('إضافة قاعدة حدود الصندوق', lang)
                    : Localization.translate('تعديل قاعدة حدود الصندوق', lang),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dropdown for Blade
                    DropdownButtonFormField<int>(
                      value: selectedBladeId,
                      decoration: InputDecoration(
                        labelText: Localization.translate('نوع الشفرة', lang),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: blades.map((b) {
                        return DropdownMenuItem<int>(
                          value: b['id'] as int,
                          child: Text(b['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            selectedBladeId = val;
                            final selectedBlade = blades.firstWhere(
                              (blade) => blade['id'] == val,
                            );
                            widthCtrl.text =
                                ((selectedBlade['max_width_mm'] as num?)
                                            ?.toDouble() ??
                                        6000)
                                    .toStringAsFixed(0);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    // Dropdown for Box Size
                    DropdownButtonFormField<int>(
                      value: selectedBoxSize,
                      decoration: InputDecoration(
                        labelText: Localization.translate('مقاس الصندوق', lang),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: boxSizes.map((size) {
                        return DropdownMenuItem<int>(
                          value: size,
                          child: Text(
                            '${Localization.translate('ملم', lang)} $size',
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            selectedBoxSize = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    // Max height input
                    TextField(
                      controller: heightCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'أقصى ارتفاع يحتمله الصندوق (ملم)',
                          lang,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: widthCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'أقصى عرض للّامة (ملم) - خاص باللامة وليس الصندوق',
                          lang,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(Localization.translate('إلغاء', lang)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final maxHeight = double.tryParse(heightCtrl.text);
                    final maxWidth = double.tryParse(widthCtrl.text);
                    if (maxHeight == null ||
                        maxHeight <= 0 ||
                        maxWidth == null ||
                        maxWidth <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'الرجاء إدخال قيم صحيحة للارتفاع والعرض.',
                              lang,
                            ),
                          ),
                        ),
                      );
                      return;
                    }

                    if (existingLimit == null) {
                      await db.insertShutterBoxLimit(
                        selectedBoxSize,
                        selectedBladeId!,
                        maxHeight,
                        maxWidth,
                      );
                    } else {
                      final id = existingLimit['id'] as int;
                      await db.updateShutterBoxLimit(
                        id,
                        selectedBoxSize,
                        selectedBladeId!,
                        maxHeight,
                        maxWidth,
                      );
                    }

                    Navigator.pop(ctx);
                    _loadAllData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(Localization.translate('حفظ', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCostCalculationSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Consumer<AppSettingsProvider>(
          builder: (context, settings, _) {
            final lang = settings.language;
            return AlertDialog(
              title: Text(Localization.translate('احتساب التكلفة', lang)),
              content: SizedBox(
                width: 520,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.price_check_rounded,
                    color: Colors.blue,
                  ),
                  title: Text(
                    Localization.translate(
                      'أسعار الشراء تُطبَّق تلقائياً على جدول الكمية والتكلفة',
                      lang,
                    ),
                  ),
                  subtitle: Text(
                    Localization.translate(
                      'عند كل شراء يصبح السعر هو المتوسط المرجّح بين المخزون الحالي والكمية الجديدة، وإذا كان المخزون صفراً يُعتمد سعر الشراء الجديد مباشرة. يظهر آخر سعر شراء في الفاتورة ويمكن تعديله.',
                      lang,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إغلاق', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage lang = Provider.of<AppSettingsProvider>(context).language;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(Localization.translate('إدارة الأسعار', lang)),
        centerTitle: true,
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.layers_outlined),
            label: Text(
              switch (lang) {
                AppLanguage.french => 'Panneaux',
                AppLanguage.english => 'Sheets',
                _ => 'الألواح والبانوهات',
              },
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const StandardSheetsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calculate_outlined, color: Colors.white),
            tooltip: Localization.translate('احتساب التكلفة', lang),
            onPressed: _showCostCalculationSettings,
          ),
          IconButton(
            icon: const Icon(Icons.sync_alt_rounded, color: Colors.white),
            tooltip: Localization.translate('مزامنة الأسعار', lang),
            onPressed: () => showPriceSyncSettingsDialog(
              context,
              onPriceUpdated: _loadAllData,
            ),
          ),
        ],
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: Localization.translate("الألمنيوم (السلاسل)", lang)),
            Tab(text: Localization.translate("ألوان الأنظمة", lang)),
            Tab(text: Localization.translate("الزجاج", lang)),
            Tab(
              icon: const Icon(Icons.layers_outlined, size: 18),
              text: switch (lang) {
                AppLanguage.french => 'Prix panneaux et verre',
                AppLanguage.english => 'Panel & glass prices',
                _ => 'أسعار الألواح والبانوهات والزجاج',
              },
            ),
            Tab(text: Localization.translate("الستائر", lang)),
            Tab(text: Localization.translate("الجوانات", lang)),
            Tab(text: Localization.translate("الإكسسوارات", lang)),
            Tab(text: Localization.translate("أسعار المقاطع", lang)),
            Tab(text: Localization.translate("حدود الصناديق (Caissons)", lang)),
            const Tab(text: 'Caisson Tunnel'),
            Tab(
              text: switch (lang) {
                AppLanguage.french => 'Accessoires Verre Trempé',
                AppLanguage.english => 'Tempered Glass Acc.',
                _ => 'إكسسوارات الزجاج المقسّى',
              },
            ),
          ],
        ),
      ),
      body: PageStorage(
        bucket: _scrollStorage,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildSeriesColorTab(context),
                  _buildProfileColorsTab(context),
                  Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.layers_outlined,
                          color: Colors.blueAccent,
                        ),
                        title: Text(
                          switch (lang) {
                            AppLanguage.arabic => 'أسعار ومقاسات الألواح الكاملة',
                            AppLanguage.french => 'Prix et formats des panneaux',
                            AppLanguage.english => 'Full sheet sizes and prices',
                          },
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          switch (lang) {
                            AppLanguage.arabic => 'الزجاج، الريزين، الأليكوبوند، البانو ساندويتش والبيكسي جلاس',
                            AppLanguage.french => 'Verre, résine, Alucobond, panneau sandwich et Plexiglas',
                            AppLanguage.english => 'Glass, resin, Alucobond, sandwich panels and Plexiglas',
                          },
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StandardSheetsScreen(),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      PriceSyncBanner(
                        categoryKey: 'glass',
                        onPriceUpdated: _loadAllData,
                      ),
                      Expanded(child: _buildGlassList(context)),
                    ],
                  ),
                  const StandardSheetsScreen(),
                  _buildShutterPricingTab(context),
                  Column(
                    children: [
                      PriceSyncBanner(
                        categoryKey: 'joints',
                        onPriceUpdated: _loadAllData,
                      ),
                      Expanded(
                        child: _buildList(
                          context,
                          jointList,
                          'Joints',
                          'name',
                          'price_per_meter',
                          Localization.translate('سعر المتر الطولي', lang),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      PriceSyncBanner(
                        categoryKey: 'accessories',
                        onPriceUpdated: _loadAllData,
                      ),
                      Expanded(child: _buildAccessoryColorTab(context)),
                    ],
                  ),
                  Column(
                    children: [
                      PriceSyncBanner(
                        categoryKey: 'profiles',
                        onPriceUpdated: _loadAllData,
                      ),
                      Expanded(child: _buildSectionPricingTab(context)),
                    ],
                  ),
                  _buildShutterBoxLimitsTab(context),
                  Column(
                    children: [
                      PriceSyncBanner(
                        categoryKey: 'caisson_tunnel',
                        onPriceUpdated: _loadAllData,
                      ),
                      Expanded(child: _buildCaissonTunnelPricingTab(context)),
                    ],
                  ),
                  Column(
                    children: [
                      PriceSyncBanner(
                        categoryKey: 'tempered_glass',
                        onPriceUpdated: _loadAllData,
                      ),
                      Expanded(child: _buildTemperedGlassPricingTab(context)),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _showCustomizeAccessoryColorsDialog({int? initialAccId}) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    int? selectedAccId = initialAccId;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final aColors = selectedAccId != null
                ? (accessoryColorPrices[selectedAccId] ?? {})
                : {};

            // Filter accessoryList by searchQuery
            final filteredAccList = accessoryList.where((acc) {
              final name = acc['name'].toString().toLowerCase();
              return name.contains(searchQuery.toLowerCase());
            }).toList();

            // Ensure selected item stays in the list to avoid dropdown assertion error
            if (selectedAccId != null &&
                !filteredAccList.any((acc) => acc['id'] == selectedAccId)) {
              final selectedAcc = accessoryList.firstWhere(
                (acc) => acc['id'] == selectedAccId,
                orElse: () => {},
              );
              if (selectedAcc.isNotEmpty) {
                filteredAccList.insert(0, selectedAcc);
              }
            }

            return AlertDialog(
              title: Text(
                Localization.translate('تخصيص ألوان الإكسسوارات', lang),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'بحث عن إكسسوار...',
                          lang,
                        ),
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setStateDialog(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'اختر الإكسسوار',
                          lang,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      value: selectedAccId,
                      items: filteredAccList.map((acc) {
                        return DropdownMenuItem<int>(
                          value: acc['id'] as int,
                          child: Text(acc['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedAccId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (selectedAccId == null)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          Localization.translate(
                            'الرجاء اختيار إكسسوار أولاً لتخصيص ألوانه.',
                            lang,
                          ),
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Expanded(
                        child: allColorList.isEmpty
                            ? Center(
                                child: Text(
                                  Localization.translate(
                                    'لا توجد ألوان.',
                                    lang,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: allColorList.length,
                                itemBuilder: (cCtx, index) {
                                  final color = allColorList[index];
                                  final cId = color['id'] as int;
                                  final isMapped = aColors.containsKey(cId);

                                  return CheckboxListTile(
                                    title: Text(color['name'].toString()),
                                    secondary: _buildColorCircle(
                                      color,
                                      size: 24,
                                    ),
                                    value: isMapped,
                                    onChanged: (val) async {
                                      final dbInstance = (await db.db)!;
                                      if (val == true) {
                                        final acc = accessoryList.firstWhere(
                                          (a) => a['id'] == selectedAccId,
                                        );
                                        final basePrice = (acc['price'] is num)
                                            ? (acc['price'] as num).toDouble()
                                            : 0.0;
                                        await dbInstance.insert(
                                          'AccessoryColorPrices',
                                          {
                                            'accessory_id': selectedAccId,
                                            'color_id': cId,
                                            'price': basePrice,
                                          },
                                          conflictAlgorithm:
                                              ConflictAlgorithm.replace,
                                        );
                                      } else {
                                        await dbInstance.delete(
                                          'AccessoryColorPrices',
                                          where:
                                              'accessory_id = ? AND color_id = ?',
                                          whereArgs: [selectedAccId, cId],
                                        );
                                      }
                                      CloudSyncService().notifyChange();
                                      await _loadAllData();
                                      setStateDialog(() {});
                                    },
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إغلاق', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCustomizeShutterColorsDialog() async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    int? selectedShutId;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final sColors = selectedShutId != null
                ? (shutterColorPrices[selectedShutId] ?? {})
                : {};

            return AlertDialog(
              title: Text(
                Localization.translate('تخصيص ألوان مركبات ستائر', lang),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: Localization.translate('اختر المكون', lang),
                        border: const OutlineInputBorder(),
                      ),
                      value: selectedShutId,
                      items: shutterList.map((sh) {
                        return DropdownMenuItem<int>(
                          value: sh['id'] as int,
                          child: Text(sh['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedShutId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (selectedShutId == null)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          Localization.translate(
                            'الرجاء اختيار مكون أولاً لتخصيص ألوانه.',
                            lang,
                          ),
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Expanded(
                        child: allColorList.isEmpty
                            ? Center(
                                child: Text(
                                  Localization.translate(
                                    'لا توجد ألوان.',
                                    lang,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: allColorList.length,
                                itemBuilder: (cCtx, index) {
                                  final color = allColorList[index];
                                  final cId = color['id'] as int;
                                  final isMapped = sColors.containsKey(cId);
                                  final isGreyBaseColor =
                                      _isShutterGreyBaseColor(color);

                                  return CheckboxListTile(
                                    title: Text(
                                      isGreyBaseColor
                                          ? Localization.translate(
                                              'رمادي (السعر الأساسي)',
                                              lang,
                                            )
                                          : Localization.translate(
                                              color['name'].toString(),
                                              lang,
                                            ),
                                    ),
                                    secondary: _buildColorCircle(
                                      color,
                                      size: 24,
                                    ),
                                    value: isMapped,
                                    onChanged: isGreyBaseColor
                                        ? null
                                        : (val) async {
                                            if (val == true) {
                                              final shut = shutterList
                                                  .firstWhere(
                                                    (s) =>
                                                        s['id'] ==
                                                        selectedShutId,
                                                  );
                                              final basePrice =
                                                  _readStoredPrice(
                                                    shut['price'],
                                                  );
                                              await db
                                                  .setShutterColorForComponent(
                                                    shutterComponentId:
                                                        selectedShutId!,
                                                    colorId: cId,
                                                    enabled: true,
                                                    price: basePrice,
                                                  );
                                            } else {
                                              await db
                                                  .setShutterColorForComponent(
                                                    shutterComponentId:
                                                        selectedShutId!,
                                                    colorId: cId,
                                                    enabled: false,
                                                  );
                                            }
                                            await _loadAllData();
                                            setStateDialog(() {});
                                          },
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إغلاق', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_persistSelectedTab);
    _reloadDebounce?.cancel();
    _tabController.dispose();
    _dbSubscription?.cancel();
    super.dispose();
  }
}

class PriceEditRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final double currentPrice;
  final bool canChangePrices;
  final Function(double) onSave;
  final Widget? titleIcon;
  final ValueChanged<double?>? onPriceChanged;
  final VoidCallback? onSaveCompleted;

  const PriceEditRow({
    Key? key,
    required this.title,
    this.subtitle = '',
    required this.currentPrice,
    required this.canChangePrices,
    required this.onSave,
    this.titleIcon,
    this.onPriceChanged,
    this.onSaveCompleted,
  }) : super(key: key);

  @override
  State<PriceEditRow> createState() => _PriceEditRowState();
}

class _PriceEditRowState extends State<PriceEditRow> {
  late TextEditingController _ctrl;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _showSaved = false;

  String _normalisePriceInput(String value) {
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    var normalized = value.trim();
    for (var index = 0; index < arabicDigits.length; index++) {
      normalized = normalized
          .replaceAll(arabicDigits[index], index.toString())
          .replaceAll(persianDigits[index], index.toString());
    }
    return normalized
        .replaceAll('٬', '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(',', '.')
        .replaceAll('٫', '.');
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentPrice.toString());
  }

  @override
  void didUpdateWidget(PriceEditRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPrice != widget.currentPrice && !_isEditing) {
      _ctrl.text = widget.currentPrice.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (widget.titleIcon != null) ...[
                      widget.titleIcon!,
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.subtitle.isNotEmpty)
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _ctrl,
              readOnly: !_isEditing || !widget.canChangePrices,
              onChanged: (value) {
                if (!_isEditing) return;
                final normalizedPrice = _normalisePriceInput(value);
                final parsed = double.tryParse(normalizedPrice);
                widget.onPriceChanged?.call(parsed);
              },
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(
                color: _isEditing
                    ? (isDark ? Colors.white : Colors.black)
                    : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                fontWeight: _isEditing ? FontWeight.bold : FontWeight.normal,
              ),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: _isEditing
                        ? Colors.blue
                        : (isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300),
                    width: _isEditing ? 2 : 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: _isEditing
                        ? Colors.blue
                        : (isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300),
                    width: _isEditing ? 2 : 1,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixText: 'DZD',
                suffixStyle: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
                filled: true,
                fillColor: _isEditing
                    ? (isDark ? const Color(0xFF2A2A2A) : Colors.white)
                    : (isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100),
              ),
            ),
          ),
          const SizedBox(width: 8),

          if (widget.canChangePrices)
            Container(
              decoration: BoxDecoration(
                color: _isEditing
                    ? Colors.green.withValues(alpha: 0.1)
                    : (_showSaved
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.blue.withValues(alpha: 0.1)),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _isSaving
                      ? Icons.hourglass_top
                      : (_isEditing
                            ? Icons.save
                            : (_showSaved ? Icons.check_circle : Icons.edit)),
                  color: _isEditing || _showSaved ? Colors.green : Colors.blue,
                ),
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (_isEditing) {
                          final normalizedPrice = _normalisePriceInput(
                            _ctrl.text,
                          );
                          double? parsed = double.tryParse(normalizedPrice);
                          if (parsed == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate(
                                    'أدخل سعراً رقمياً صحيحاً.',
                                    lang,
                                  ),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setState(() => _isSaving = true);
                          try {
                            final result = widget.onSave(parsed);
                            if (result is Future) {
                              await result;
                            }
                            if (!mounted) return;
                            setState(() {
                              _isEditing = false;
                              _isSaving = false;
                              _showSaved = true;
                            });
                            widget.onSaveCompleted?.call();
                            Future<void>.delayed(
                              const Duration(seconds: 2),
                              () {
                                if (mounted && !_isEditing) {
                                  setState(() => _showSaved = false);
                                }
                              },
                            );
                          } catch (_) {
                            if (!mounted) return;
                            setState(() => _isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.red,
                                content: Text(
                                  Localization.translate(
                                    'تعذر حفظ السعر. حاول مرة أخرى.',
                                    lang,
                                  ),
                                ),
                              ),
                            );
                          }
                        } else {
                          setState(() {
                            _isEditing = true;
                            _showSaved = false;
                          });
                        }
                      },
              ),
            ),
        ],
      ),
    );
  }
}
