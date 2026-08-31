import 'package:flutter/material.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/show_system_francais.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/selected_systems_screen.dart';
import 'package:database_data/Screen/caisson_tunnel_screen.dart';
import 'package:database_data/Screen/moustiquaire_screen.dart';
import 'package:database_data/Screen/tempered_glass_work_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChooseSysteme extends StatefulWidget {
  final Map<String, dynamic>? initialSettings;
  const ChooseSysteme({super.key, this.initialSettings});

  @override
  State<ChooseSysteme> createState() => _ChooseSystemeState();
}

class _ChooseSystemeState extends State<ChooseSysteme> {
  late final SqlDatabase db = SqlDatabase();

  Map<String, bool> _activeModes = {
    'sliding': true,
    'french': true,
    'mixed': true,
    'rolling': true,
    'caisson_tunnel': true,
    'moustiquaire': true,
    'precadre': true,
    'verre': true,
  };

  @override
  void initState() {
    super.initState();
    _loadActiveModes();
  }

  Future<void> _loadActiveModes() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _activeModes = {
        'sliding': prefs.getBool('system_active_sliding') ?? true,
        'french': prefs.getBool('system_active_french') ?? true,
        'mixed': prefs.getBool('system_active_mixed') ?? true,
        'rolling': prefs.getBool('system_active_rolling') ?? true,
        'caisson_tunnel': prefs.getBool('system_active_caisson_tunnel') ?? true,
        'moustiquaire': prefs.getBool('system_active_moustiquaire') ?? true,
        'precadre': prefs.getBool('system_active_precadre') ?? true,
        'verre': prefs.getBool('system_active_verre') ?? true,
      };
    });
  }

  void _applyDrawingDefaults(WindowModel model, Map<String, dynamic> defaults) {
    bool readBool(String key, bool fallback) {
      final value = defaults[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) return value.trim().toLowerCase() == 'true';
      return fallback;
    }

    int? readInt(String key) {
      final value = defaults[key];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    double? readDouble(String key) {
      final value = defaults[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    model.hasBottomFrame = readBool('hasBottomFrame', model.hasBottomFrame);
    model.hasFramePlintheBottom = readBool(
      'hasFramePlintheBottom',
      model.hasFramePlintheBottom,
    );
    model.isInternalView = readBool('isInternalView', model.isInternalView);
    model.hasShutter = readBool('hasShutter', model.hasShutter);
    model.shutterIntercalaireRatio =
        readInt('shutterIntercalaireRatio') ?? model.shutterIntercalaireRatio;
    model.shutterMechanism =
        defaults['shutterMechanism']?.toString() ?? model.shutterMechanism;
    model.motorHasInterrupteur = readBool(
      'motorHasInterrupteur',
      model.motorHasInterrupteur,
    );
    model.motorHasTelecommande = readBool(
      'motorHasTelecommande',
      model.motorHasTelecommande,
    );
    model.shutterLame =
        defaults['shutterLame']?.toString() ?? model.shutterLame;
    model.shutterGlissiere =
        defaults['shutterGlissiere']?.toString() ?? model.shutterGlissiere;
    model.shutterPosition =
        readDouble('shutterPosition') ?? model.shutterPosition;
    model.shutterDriveSide =
        defaults['shutterDriveSide']?.toString() ?? model.shutterDriveSide;
    model.customShutterBoxHeight =
        readDouble('customShutterBoxHeight') ?? model.customShutterBoxHeight;
    model.selectedShutterLameId =
        readInt('selectedShutterLameId') ?? model.selectedShutterLameId;
    model.selectedShutterKitId =
        readInt('selectedShutterKitId') ?? model.selectedShutterKitId;
    model.selectedShutterMotorId =
        readInt('selectedShutterMotorId') ?? model.selectedShutterMotorId;
    model.useSystemOB = readBool('useSystemOB', model.useSystemOB);
    model.useDemiOB = readBool('useDemiOB', model.useDemiOB);
    model.useVerrouCentral = readBool(
      'useVerrouCentral',
      model.useVerrouCentral,
    );
    model.hasSideCovers = readBool('hasSideCovers', model.hasSideCovers);
    model.sideCoverUseSecondWidth = readBool(
      'sideCoverUseSecondWidth',
      model.sideCoverUseSecondWidth,
    );
    model.hasInternalSlidingSideCover = readBool(
      'hasInternalSlidingSideCover',
      model.hasInternalSlidingSideCover,
    );
    model.useCustomSideCoverLayout = readBool(
      'useCustomSideCoverLayout',
      model.useCustomSideCoverLayout,
    );
    if (defaults['sideCoverSegments'] is List) {
      model.sideCoverSegments = (defaults['sideCoverSegments'] as List)
          .whereType<Map>()
          .map(
            (raw) => SideCoverSegment.fromMap(Map<String, dynamic>.from(raw)),
          )
          .toList();
    }
    if (defaults['hiddenSideCoverSegments'] is List) {
      model.hiddenSideCoverSegments =
          (defaults['hiddenSideCoverSegments'] as List)
              .map((side) => side.toString().toLowerCase())
              .toSet();
    }
    model.isFrame140 = readBool('isFrame140', model.isFrame140);
    if (defaults['removedShutterSides'] is List) {
      model.removedShutterSides = (defaults['removedShutterSides'] as List)
          .map((side) => side.toString().toLowerCase())
          .toSet();
    }
    model.primaryMullionAxis = defaults['primaryMullionAxis']?.toString();

    final frameColorName = defaults['frameColor']?.toString();
    if (frameColorName != null) {
      model.frameColor = FrameColor.values.firstWhere(
        (color) => color.name == frameColorName,
        orElse: () => FrameColor.white,
      );
    }
    if (defaults['selectedDbColor'] is Map) {
      model.selectedDbColor = Map<String, dynamic>.from(
        defaults['selectedDbColor'] as Map,
      );
    }
    if (defaults['selectedAccessoryColor'] is Map) {
      model.selectedAccessoryColor = Map<String, dynamic>.from(
        defaults['selectedAccessoryColor'] as Map,
      );
    }

    Map<String, dynamic>? copyMap(String key) {
      final value = defaults[key];
      return value is Map ? Map<String, dynamic>.from(value) : null;
    }

    model.frameOverride = copyMap('frameOverride');
    model.sashOverride = copyMap('sashOverride');
    model.sideCoverOverride = copyMap('sideCoverOverride');
    model.internalSlidingSideCoverOverride = copyMap(
      'internalSlidingSideCoverOverride',
    );
    model.slidingFrameOverride = copyMap('slidingFrameOverride');
    model.slidingSashOverride = copyMap('slidingSashOverride');
    final componentOverrides = defaults['componentOverrides'];
    if (componentOverrides is Map) {
      model.componentOverrides = {
        for (final entry in componentOverrides.entries)
          entry.key.toString(): entry.value is Map
              ? Map<String, dynamic>.from(entry.value as Map)
              : entry.value,
      };
    }
  }

  WindowModel _makeModel({double w = 0, double h = 0, double thickness = 60}) {
    final m = WindowModel(
      width: w,
      height: h,
      profileThickness: thickness,
      db: db,
    );
    final s = widget.initialSettings;
    if (s != null) {
      int? readInt(dynamic value) {
        if (value is num) return value.toInt();
        return int.tryParse(value?.toString() ?? '');
      }

      final activeSeries = s['activeSeries'];
      final activeSlidingSeries = s['activeSlidingSeries'];
      if (activeSeries is AluminumSeries) m.activeSeries = activeSeries;
      if (activeSlidingSeries is AluminumSeries) {
        m.activeSlidingSeries = activeSlidingSeries;
      }
      m.loadedSeriesId = readInt(s['loadedSeriesId']);
      m.loadedSlidingSeriesId = readInt(s['loadedSlidingSeriesId']);
      m.loadedSeriesName = s['loadedSeriesName']?.toString();
      m.loadedSlidingSeriesName = s['loadedSlidingSeriesName']?.toString();
      final drawingDefaults = s['drawingDefaults'];
      if (drawingDefaults is Map) {
        _applyDrawingDefaults(m, Map<String, dynamic>.from(drawingDefaults));
      } else if (s['selectedDbColor'] is Map) {
        m.selectedDbColor = Map<String, dynamic>.from(
          s['selectedDbColor'] as Map,
        );
      }
      if (s['selectedAccessoryColor'] != null)
        m.selectedAccessoryColor = s['selectedAccessoryColor'];
      if (s['hasShutter'] == true) m.hasShutter = true;
      if (s['shutterLame'] != null) m.shutterLame = s['shutterLame'];
      if (s['shutterGlissiere'] != null)
        m.shutterGlissiere = s['shutterGlissiere'];
      if (s['shutterMechanism'] != null)
        m.shutterMechanism = s['shutterMechanism'];

      final glassSpec =
          s['glassSpec'] ??
          (drawingDefaults is Map ? drawingDefaults['glassSpec'] : null);
      if (glassSpec is Map) {
        WindowZone.globalDefaultGlass = glassSpecificationFromMap(
          Map<String, dynamic>.from(glassSpec),
        );
      } else {
        WindowZone.globalDefaultGlass = const GlassSpecification();
      }
    } else {
      WindowZone.globalDefaultGlass = const GlassSpecification();
    }

    if (m.selectedDbColor == null) {
      m.frameColor = FrameColor.white;
    }
    return m;
  }

  List<WindowModel> _moustiquaireModelsFromPayload(
    Map<String, dynamic> payload,
  ) {
    final rawItems = payload['items'];
    if (rawItems is! List) return const [];
    final models = <WindowModel>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final width = (item['widthMm'] as num?)?.toDouble() ?? 0;
      final height = (item['heightMm'] as num?)?.toDouble() ?? 0;
      if (width <= 0 || height <= 0) continue;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final area =
          (item['areaSqm'] as num?)?.toDouble() ??
          ((width / 1000) * (height / 1000));
      final totalArea =
          (item['totalAreaSqm'] as num?)?.toDouble() ?? area * quantity;
      final totalPrice = (item['estimatedPrice'] as num?)?.toDouble() ?? 0;
      final subtype =
          item['type']?.toString() ?? payload['subType']?.toString() ?? '';
      final frameColor =
          item['frameColor']?.toString() ??
          payload['frameColor']?.toString() ??
          '';
      final meshColor =
          item['meshColor']?.toString() ??
          payload['meshColor']?.toString() ??
          '';

      final singlePayload = <String, dynamic>{
        ...payload,
        'subType': subtype,
        'itemsCount': 1,
        'totalQuantity': quantity,
        'grandTotalAreaSqm': totalArea,
        'grandTotalPrice': totalPrice,
        'widthMm': width,
        'heightMm': height,
        'frameColor': frameColor,
        'meshColor': meshColor,
        'items': [item],
      };
      final model = _makeModel(w: width, h: height);
      model.isMoustiquaire = true;
      model.isReplaced = false;
      model.manualNameOverride = 'Moustiquaire ($subtype)';
      model.description =
          'النوع: $subtype | القياس: ${width.toStringAsFixed(0)} × '
          '${height.toStringAsFixed(0)} mm | الإطار: $frameColor | '
          'الشبكة: $meshColor';
      model.quantity = quantity < 1 ? 1 : quantity;
      model.moustiquairePayload = singlePayload;
      model.manualPriceOverride = model.quantity > 0
          ? totalPrice / model.quantity
          : totalPrice;
      models.add(model);
    }
    return models;
  }

  List<WindowModel> _glassWorkModelsFromPayload(Map<String, dynamic> payload) {
    final rawItems = payload['items'];
    if (rawItems is! List) return const [];
    final models = <WindowModel>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final width = (item['widthMm'] as num?)?.toDouble() ?? 0;
      final height = (item['heightMm'] as num?)?.toDouble() ?? 0;
      if (width <= 0 || height <= 0) continue;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final area =
          (item['areaSqm'] as num?)?.toDouble() ??
          ((width / 1000) * (height / 1000));
      final unitPrice =
          (item['unitPrice'] as num?)?.toDouble() ??
          area * ((item['pricePerSqm'] as num?)?.toDouble() ?? 0);
      final totalPrice =
          (item['totalPrice'] as num?)?.toDouble() ?? unitPrice * quantity;
      final workLabel = payload['workTypeLabel']?.toString() ?? 'عمل زجاجي';
      final finishLabel = payload['glassFinishLabel']?.toString() ?? 'شفاف';
      final stickerLabel = payload['stickerLabel']?.toString() ?? 'بدون ستيكر';
      final shapeLabel = payload['panelShapeLabel']?.toString() ?? 'مستقيم (I)';
      final operationLabel = payload['operationLabel']?.toString() ?? 'منزلق';
      final kitLabel = payload['selectedKitLabel']?.toString() ?? '';
      final thickness = (payload['thicknessMm'] as num?)?.toDouble() ?? 10;
      final notes = payload['notes']?.toString() ?? '';

      final singlePayload = <String, dynamic>{
        ...payload,
        'itemsCount': 1,
        'totalQuantity': quantity,
        'grandTotalAreaSqm': area * quantity,
        'grandTotalPrice': totalPrice,
        'items': [item],
      };
      final model = _makeModel(w: width, h: height);
      model.isGlassWork = true;
      model.isReplaced = false;
      model.manualNameOverride = 'Verre Trempé - $workLabel - $shapeLabel';
      model.description =
          '$operationLabel${kitLabel.isEmpty ? '' : ' | $kitLabel'} | $shapeLabel | '
          '$finishLabel ${thickness.toStringAsFixed(0)} mm | $stickerLabel | '
          '${width.toStringAsFixed(0)} × ${height.toStringAsFixed(0)} mm'
          '${notes.isEmpty ? '' : ' | $notes'}';
      model.quantity = quantity < 1 ? 1 : quantity;
      model.glassWorkPayload = singlePayload;
      model.manualPriceOverride = unitPrice;
      models.add(model);
    }
    return models;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context).language;

    // There is one user-facing entry point for windows and doors.  Whether a
    // zone is opening, sliding or uses a shutter is determined later by the
    // selected series definition; those are not separate drawing screens.
    final systemItems = <Widget>[
      ItemBuildSystem(
        width: 70,
        height: 70,
        title: Localization.translate('التصميم', lang),
        iconPath: 'Icon/french.png',
        onTap: () => _navigateToSystem(context, 'mixed'),
      ),
    ];
    const showLegacySystemCards = false;

    if (showLegacySystemCards && (_activeModes['sliding'] ?? true)) {
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'System Sliding (جرار)',
          iconPath: 'Icon/sli.png',
          onTap: () => _navigateToSystem(context, 'sliding'),
        ),
      );
    }

    if (showLegacySystemCards && (_activeModes['french'] ?? true)) {
      if (systemItems.isNotEmpty)
        systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 70,
          height: 70,
          title: 'System Beating (فرنسي)',
          iconPath: 'Icon/french.png',
          onTap: () => _navigateToSystem(context, 'french'),
        ),
      );
    }

    if (showLegacySystemCards && (_activeModes['mixed'] ?? true)) {
      if (systemItems.isNotEmpty)
        systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'Conception (التصميم)',
          iconPath: 'Icon/french.png',
          onTap: () => _navigateToSystem(context, 'mixed'),
        ),
      );
    }

    if (showLegacySystemCards && (_activeModes['rolling'] ?? true)) {
      if (systemItems.isNotEmpty)
        systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'System Roling',
          iconPath: 'Icon/roling.png',
          onTap: () => _navigateToSystem(context, ''),
        ),
      );
    }

    if (_activeModes['caisson_tunnel'] ?? true) {
      if (systemItems.isNotEmpty)
        systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'Caisson Tunnel',
          iconPath: 'Icon/caisson_tunnel.jpg',
          onTap: () => _navigateToSystem(context, 'caisson_tunnel'),
        ),
      );
    }

    if (_activeModes['moustiquaire'] ?? true) {
      if (systemItems.isNotEmpty)
        systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: Localization.translate('Moustiquaire (موستيكير)', lang),
          iconPath: 'Icon/media.webp',
          onTap: () => _navigateToSystem(context, 'moustiquaire'),
        ),
      );
    }

    if (_activeModes['precadre'] ?? true) {
      if (systemItems.isNotEmpty)
        systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: 'Pre-cadre',
          iconPath: 'Icon/french.png',
          onTap: () => _navigateToSystem(context, 'precadre'),
        ),
      );
    }

    if (_activeModes['verre'] ?? true) {
      if (systemItems.isNotEmpty)
        systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      systemItems.add(
        ItemBuildSystem(
          width: 60,
          height: 60,
          title: Localization.translate('Verre Trempé (أعمال الزجاج)', lang),
          iconPath: 'Icon/verre.png',
          onTap: () => _navigateToSystem(context, 'verre'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        title: Text(
          Localization.translate("نظام الورشة - اختيار النظام", lang),
        ),
        centerTitle: true,
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (false)
            IconButton(
              tooltip: Localization.translate('تعديل الأنظمة المفعلة', lang),
              icon: const Icon(Icons.tune_rounded),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SelectedSystemsScreen(),
                  ),
                );
                _loadActiveModes();
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // قسم العنوان
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.window,
                    color: isDark ? Colors.blue.shade300 : Colors.blue,
                    size: 30,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    Localization.translate('اختر نظام العمل', lang),
                    style: TextStyle(
                      fontSize: 22,
                      color: isDark ? Colors.blue.shade300 : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    Localization.translate(
                      'حدد نوع النافذة للبدء في الحسابات',
                      lang,
                    ),
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // قائمة الأنظمة المحدثة بناءً على الإعدادات النشطة
            if (systemItems.isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 30,
                ),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 48,
                      color: Colors.orange.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      Localization.translate(
                        'جميع أنظمة العمل معطلة حالياً بالورشة.',
                        lang,
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Localization.translate(
                        'يمكنك تفعيل الأنظمة التي تستعملها بالضغط على زر الضبط أعلاه.',
                        lang,
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(
                        Localization.translate('تعديل الأنظمة المفعلة', lang),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SelectedSystemsScreen(),
                          ),
                        );
                        _loadActiveModes();
                      },
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  border: Border.all(
                    width: 1,
                    color: isDark ? Colors.grey.shade800 : Colors.grey,
                  ),
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.2),
                      spreadRadius: 5,
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(children: systemItems),
              ),
            const SizedBox(height: 500),
          ],
        ),
      ),
    );
  }

  void _navigateToSystem(BuildContext context, String systemType) async {
    if (systemType == 'caisson_tunnel') {
      final caissonResult = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CaissonTunnelScreen()),
      );
      if (caissonResult != null &&
          caissonResult is Map<String, dynamic> &&
          context.mounted) {
        final int cBars = (caissonResult['grandTotalCaissonBars'] as int? ?? 0);
        final int bBars =
            (caissonResult['grandTotalBottomCoverBars'] as int? ?? 0);
        final int pairs = (caissonResult['grandTotalPairs'] as int? ?? 0);

        // Compute suggested price from DB
        double suggestedPrice = 0.0;
        try {
          final ctPrices = await db.getCaissonTunnelPrices();
          if (ctPrices.isNotEmpty) {
            final priceRow = ctPrices.first;
            final profileBar = (priceRow['profile_price_per_bar'] as num? ?? 0)
                .toDouble();
            final bottomBar =
                (priceRow['bottom_cover_price_per_bar'] as num? ?? 0)
                    .toDouble();
            suggestedPrice = (cBars * profileBar) + (bBars * bottomBar);
          }
        } catch (_) {}

        if (!context.mounted) return;
        final model = _makeModel(w: 1000, h: 300);
        model.isCaissonTunnel = true;
        model.isReplaced = false;
        model.manualNameOverride = 'Caisson Tunnel';
        model.description =
            'Kit: ${caissonResult['kitType']} | Barres caisson: $cBars (6m) | Fond: $bBars (6m) | Paires: $pairs';
        model.quantity = 1;
        model.caissonPayload = caissonResult;
        if (suggestedPrice > 0) {
          model.manualPriceOverride = suggestedPrice;
        }

        Navigator.pop(context, model);
      }
      return;
    }

    if (systemType == 'moustiquaire') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MoustiquaireScreen()),
      );
      if (result != null && result is Map<String, dynamic> && context.mounted) {
        final models = _moustiquaireModelsFromPayload(result);
        if (models.isNotEmpty) Navigator.pop(context, models);
      }
      return;
    }

    if (systemType == 'verre') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TemperedGlassWorkScreen(),
        ),
      );
      if (result != null && result is Map<String, dynamic> && context.mounted) {
        final models = _glassWorkModelsFromPayload(result);
        if (models.isNotEmpty) Navigator.pop(context, models);
      }
      return;
    }

    Widget targetPage;

    switch (systemType) {
      case 'sliding':
        targetPage = WindowView(
          systemMode: 'sliding',
          model: _makeModel(thickness: 45),
        );
        break;
      case 'french':
        targetPage = WindowView(
          systemMode: 'french',
          model: _makeModel(thickness: 60),
        );
        break;
      case 'mixed':
        targetPage = WindowView(
          systemMode: 'mixed',
          model: _makeModel(thickness: 60),
        );
        break;
      case 'rolling':
        targetPage = WindowView(model: _makeModel(thickness: 30));
        break;
      default:
        targetPage = WindowView(systemMode: 'mixed', model: _makeModel());
        break;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => targetPage),
    );

    if (result != null) {
      if (context.mounted) Navigator.pop(context, result);
    }
  }
}

//==========================================ItemBuildSystem================================
class ItemBuildSystem extends StatefulWidget {
  final String title;
  final String iconPath;
  final VoidCallback onTap;
  final double? width;

  final double? height;

  const ItemBuildSystem({
    super.key,
    required this.title,
    required this.iconPath,
    required this.onTap,
    this.width,
    this.height,
  });

  @override
  State<ItemBuildSystem> createState() => _ItemBuildSystemState();
}

class _ItemBuildSystemState extends State<ItemBuildSystem> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      borderRadius: BorderRadius.circular(10),
      color: isDark ? Colors.transparent : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
          child: Row(
            children: [
              if (widget.title.toLowerCase().contains('mixed') ||
                  widget.title.contains('مختلط'))
                SizedBox(
                  width: widget.width ?? 60,
                  height: widget.height ?? 60,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: (widget.width ?? 60) * 0.65,
                        child: Image.asset(
                          'Icon/french.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                                size: 24,
                              ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: (widget.width ?? 60) * 0.65,
                        child: Image.asset(
                          'Icon/sli.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                                size: 24,
                              ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Image.asset(
                  widget.iconPath,
                  width: widget.width,
                  height: widget.height,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
              const SizedBox(width: 20),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
