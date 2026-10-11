import 'dart:async';
import 'package:database_data/widgets/app_material.dart';
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
import 'package:database_data/services/cloud_sync_service.dart';
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

  int? _defaultOpeningSeriesId;
  int? _defaultSlidingSeriesId;
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadActiveModes();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) _loadActiveModes();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _readLocalModes() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _defaultOpeningSeriesId = prefs.getInt('default_opening_series_id');
      _defaultSlidingSeriesId = prefs.getInt('default_sliding_series_id');
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

  Future<void> _loadActiveModes() async {
    await _readLocalModes();
    try {
      await CloudSyncService().loadAndApplyWorkshopSystems().timeout(
        const Duration(seconds: 12),
        onTimeout: () {},
      );
      if (mounted) {
        await _readLocalModes();
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadActiveSeriesList() async {
    final d = await db.db;
    if (d == null) return [];
    return await d.rawQuery('''
      SELECT s.id, s.name, s.type, s.profile_id, p.name as profile_name 
      FROM Series s 
      LEFT JOIN Profile p ON s.profile_id = p.id 
      WHERE (s.is_active = 1 OR s.is_active IS NULL)
        AND (p.is_active = 1 OR p.is_active IS NULL)
      ORDER BY p.name, s.name
    ''');
  }

  Future<void> _showDefaultSeriesDialog(
    BuildContext context,
    AppLanguage lang,
  ) async {
    final seriesList = await _loadActiveSeriesList();
    if (!mounted) return;

    int? tempOpeningId = _defaultOpeningSeriesId;
    int? tempSlidingId = _defaultSlidingSeriesId;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF232336) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Localization.translate('السلاسل الافتراضية للورشة', lang),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Localization.translate(
                        'حدد السلسلة التي تفتح بها النوافذ الجديدة تلقائياً بدون الحاجة لتغييرها في كل مرة:',
                        lang,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      Localization.translate(
                        'سلسلة الفتح الافتراضية (Battant):',
                        lang,
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<int?>(
                        value: seriesList.any((s) => s['id'] == tempOpeningId)
                            ? tempOpeningId
                            : null,
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor: isDark
                            ? const Color(0xFF2A2A3E)
                            : Colors.white,
                        hint: Text(
                          Localization.translate(
                            'تلقائي (افتراضي النظام)',
                            lang,
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              Localization.translate(
                                'تلقائي (افتراضي النظام)',
                                lang,
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          ...seriesList.map((s) {
                            final profileName = s['profile_name'] ?? '';
                            final seriesName = s['name'] ?? '';
                            return DropdownMenuItem<int?>(
                              value: s['id'] as int,
                              child: Text(
                                profileName.toString().isNotEmpty
                                    ? '$seriesName [$profileName]'
                                    : seriesName.toString(),
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setDialogState(() => tempOpeningId = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      Localization.translate(
                        'سلسلة المنزلق الافتراضية (Coulissant):',
                        lang,
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.green.shade300
                            : Colors.green.shade800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<int?>(
                        value: seriesList.any((s) => s['id'] == tempSlidingId)
                            ? tempSlidingId
                            : null,
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor: isDark
                            ? const Color(0xFF2A2A3E)
                            : Colors.white,
                        hint: Text(
                          Localization.translate(
                            'تلقائي (افتراضي النظام)',
                            lang,
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              Localization.translate(
                                'تلقائي (افتراضي النظام)',
                                lang,
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          ...seriesList.map((s) {
                            final profileName = s['profile_name'] ?? '';
                            final seriesName = s['name'] ?? '';
                            return DropdownMenuItem<int?>(
                              value: s['id'] as int,
                              child: Text(
                                profileName.toString().isNotEmpty
                                    ? '$seriesName [$profileName]'
                                    : seriesName.toString(),
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setDialogState(() => tempSlidingId = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إلغاء', lang)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.blue.shade700
                        : Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    if (tempOpeningId != null) {
                      await prefs.setInt(
                        'default_opening_series_id',
                        tempOpeningId!,
                      );
                    } else {
                      await prefs.remove('default_opening_series_id');
                    }
                    if (tempSlidingId != null) {
                      await prefs.setInt(
                        'default_sliding_series_id',
                        tempSlidingId!,
                      );
                    } else {
                      await prefs.remove('default_sliding_series_id');
                    }
                    if (mounted) {
                      setState(() {
                        _defaultOpeningSeriesId = tempOpeningId;
                        _defaultSlidingSeriesId = tempSlidingId;
                      });
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'تم حفظ السلاسل الافتراضية بنجاح',
                              lang,
                            ),
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 2),
                        ),
                      );
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
    model.showInternalHardware = readBool(
      'showInternalHardware',
      model.showInternalHardware,
    );
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
    if (model.hasSideCovers) {
      model.multiFrameSideCoverManuallyEnabled = true;
    }
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
    final rawItems = payload['items'] as List?;
    final overallWidth =
        (payload['overallWidthMm'] as num?)?.toDouble() ??
        (payload['widthMm'] as num?)?.toDouble() ??
        1000.0;
    final overallHeight =
        (payload['overallHeightMm'] as num?)?.toDouble() ??
        (payload['heightMm'] as num?)?.toDouble() ??
        2000.0;

    double totalArea =
        (payload['grandTotalAreaSqm'] as num?)?.toDouble() ?? 0.0;
    double totalPrice = (payload['grandTotalPrice'] as num?)?.toDouble() ?? 0.0;

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final glassBaseName = switch (lang) {
      AppLanguage.french => 'Verre trempé',
      AppLanguage.english => 'Tempered glass',
      AppLanguage.arabic => 'زجاج مقسّى',
    };
    final panelsPrefix = switch (lang) {
      AppLanguage.french => 'Panneaux',
      AppLanguage.english => 'Panels',
      AppLanguage.arabic => 'الألواح',
    };
    final overallPrefix = switch (lang) {
      AppLanguage.french => 'Dimensions totales',
      AppLanguage.english => 'Overall dimensions',
      AppLanguage.arabic => 'القياس الإجمالي',
    };
    final mmUnit = switch (lang) {
      AppLanguage.arabic => 'مم',
      _ => 'mm',
    };

    final panelDescriptions = <String>[];
    if (rawItems != null) {
      for (var i = 0; i < rawItems.length; i++) {
        final item = rawItems[i];
        if (item is! Map) continue;
        final w = (item['widthMm'] as num?)?.toDouble() ?? 0.0;
        final h = (item['heightMm'] as num?)?.toDouble() ?? 0.0;
        final role = item['role']?.toString() ?? 'panel';
        final roleLabel = switch (role) {
          'door' => switch (lang) {
            AppLanguage.french => 'Porte',
            AppLanguage.english => 'Door',
            AppLanguage.arabic => 'باب',
          },
          'fixed' => switch (lang) {
            AppLanguage.french => 'Fixe',
            AppLanguage.english => 'Fixed',
            AppLanguage.arabic => 'ثابت',
          },
          'vitrine_left' => switch (lang) {
            AppLanguage.french => 'Vantail gauche',
            AppLanguage.english => 'Left leaf',
            AppLanguage.arabic => 'درفة يسرى',
          },
          'vitrine_right' => switch (lang) {
            AppLanguage.french => 'Vantail droit',
            AppLanguage.english => 'Right leaf',
            AppLanguage.arabic => 'درفة يمنى',
          },
          _ => switch (lang) {
            AppLanguage.french => 'Panneau ${i + 1}',
            AppLanguage.english => 'Panel ${i + 1}',
            AppLanguage.arabic => 'لوح ${i + 1}',
          },
        };
        final area =
            (item['areaSqm'] as num?)?.toDouble() ?? ((w / 1000) * (h / 1000));
        if (totalArea == 0.0) totalArea += area;
        final up = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
        if (totalPrice == 0.0) totalPrice += up;
        panelDescriptions.add(
          '$roleLabel: ${w.toStringAsFixed(0)} × ${h.toStringAsFixed(0)} $mmUnit',
        );
      }
    }

    final workLabel =
        payload['workTypeLabel']?.toString() ??
        (lang == AppLanguage.french
            ? 'Cabine de douche'
            : (lang == AppLanguage.english ? 'Shower cabin' : 'كابين دوش'));
    final finishLabel =
        payload['glassTypeLabel']?.toString() ??
        payload['glassFinishLabel']?.toString() ??
        (lang == AppLanguage.french
            ? 'Transparent'
            : (lang == AppLanguage.english ? 'Clear' : 'شفاف'));
    final thickness =
        (payload['glassThicknessMm'] ?? payload['thicknessMm'] as num?)
            ?.toDouble() ??
        10.0;
    final sablageMode = payload['sablageMode']?.toString() ?? 'none';
    final sablageLabel = switch (sablageMode) {
      'full' => switch (lang) {
        AppLanguage.french => 'Sablage complet',
        AppLanguage.english => 'Full frosting',
        AppLanguage.arabic => 'سابلاج كامل',
      },
      'decorative' => switch (lang) {
        AppLanguage.french => 'Sablage décoratif',
        AppLanguage.english => 'Decorative frosting',
        AppLanguage.arabic => 'سابلاج ديكور',
      },
      _ => switch (lang) {
        AppLanguage.french => 'Sans sablage',
        AppLanguage.english => 'No frosting',
        AppLanguage.arabic => 'بدون سابلاج',
      },
    };

    final model = _makeModel(w: overallWidth, h: overallHeight);
    model.isGlassWork = true;
    model.isReplaced = false;
    model.manualNameOverride = '$glassBaseName - $workLabel';

    final panelsSummary = panelDescriptions.isNotEmpty
        ? ' | $panelsPrefix: ${panelDescriptions.join(" ، ")}'
        : '';
    model.description =
        '$glassBaseName | $workLabel | $finishLabel ${thickness.toStringAsFixed(0)} $mmUnit | $sablageLabel'
        ' | $overallPrefix: ${overallWidth.toStringAsFixed(0)} × ${overallHeight.toStringAsFixed(0)} $mmUnit'
        '$panelsSummary';

    model.quantity = 1;
    model.glassWorkPayload = Map<String, dynamic>.from(payload);
    model.manualPriceOverride = totalPrice > 0 ? totalPrice : null;

    return [model];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(context).language;

    // The drawing page must follow the system-mode selection screen.  Keep
    // each mode as its own entry point: active modes are systems, not series.
    final systemItems = <Widget>[];

    void addSystem({
      required String mode,
      required String title,
      required String iconPath,
      double size = 60,
    }) {
      if (systemItems.isNotEmpty) {
        systemItems.add(const Divider(height: 1, indent: 10, endIndent: 10));
      }
      systemItems.add(
        ItemBuildSystem(
          width: size,
          height: size,
          title: Localization.translate(title, lang),
          iconPath: iconPath,
          onTap: () => _navigateToSystem(context, mode),
        ),
      );
    }

    if (_activeModes['mixed'] ?? true) {
      addSystem(
        mode: 'mixed',
        title: 'التصميم',
        iconPath: 'Icon/french.png',
        size: 70,
      );
    }

    if (_activeModes['sliding'] ?? true) {
      addSystem(
        mode: 'sliding',
        title: 'System Sliding (جرار)',
        iconPath: 'Icon/sli.png',
      );
    }

    if (_activeModes['french'] ?? true) {
      addSystem(
        mode: 'french',
        title: 'System Beating (فرنسي)',
        iconPath: 'Icon/french.png',
        size: 70,
      );
    }

    if (_activeModes['rolling'] ?? true) {
      addSystem(
        mode: 'rolling',
        title: 'System Roling',
        iconPath: 'Icon/roling.png',
      );
    }

    if (_activeModes['caisson_tunnel'] ?? true) {
      addSystem(
        mode: 'caisson_tunnel',
        title: 'Caisson Tunnel',
        iconPath: 'Icon/caisson_tunnel.jpg',
      );
    }

    if (_activeModes['moustiquaire'] ?? true) {
      addSystem(
        mode: 'moustiquaire',
        title: 'Moustiquaire (موستيكير)',
        iconPath: 'Icon/media.webp',
      );
    }

    if (_activeModes['precadre'] ?? true) {
      addSystem(
        mode: 'precadre',
        title: 'Pre-cadre',
        iconPath: 'Icon/french.png',
      );
    }

    if (_activeModes['verre'] ?? true) {
      addSystem(
        mode: 'verre',
        title: 'Verre Trempé (أعمال الزجاج)',
        iconPath: 'Icon/verre.png',
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
          IconButton(
            tooltip: Localization.translate('السلاسل الافتراضية', lang),
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showDefaultSeriesDialog(context, lang),
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
                  OutlinedButton.icon(
                    onPressed: () => _showDefaultSeriesDialog(context, lang),
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(
                      Localization.translate('السلاسل الافتراضية', lang),
                    ),
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

    if (_defaultOpeningSeriesId == null && _defaultSlidingSeriesId == null) {
      final defaults = await SharedPreferences.getInstance();
      if (!context.mounted) return;
      _defaultOpeningSeriesId = defaults.getInt('default_opening_series_id');
      _defaultSlidingSeriesId = defaults.getInt('default_sliding_series_id');
    }

    switch (systemType) {
      case 'sliding':
        final model = _makeModel(thickness: 45);
        if (_defaultSlidingSeriesId != null && model.loadedSeriesId == null) {
          model.loadedSeriesId = _defaultSlidingSeriesId;
          model.loadedSlidingSeriesId = _defaultSlidingSeriesId;
        }
        targetPage = WindowView(systemMode: 'sliding', model: model);
        break;
      case 'french':
        final model = _makeModel(thickness: 60);
        if (_defaultOpeningSeriesId != null && model.loadedSeriesId == null) {
          model.loadedSeriesId = _defaultOpeningSeriesId;
        }
        targetPage = WindowView(systemMode: 'french', model: model);
        break;
      case 'mixed':
        final model = _makeModel(thickness: 60);
        if (_defaultOpeningSeriesId != null && model.loadedSeriesId == null) {
          model.loadedSeriesId = _defaultOpeningSeriesId;
        }
        if (_defaultSlidingSeriesId != null &&
            model.loadedSlidingSeriesId == null) {
          model.loadedSlidingSeriesId = _defaultSlidingSeriesId;
        }
        targetPage = WindowView(systemMode: 'mixed', model: model);
        break;
      case 'rolling':
        targetPage = WindowView(
          systemMode: 'rolling',
          model: _makeModel(thickness: 30),
        );
        break;
      default:
        targetPage = WindowView(systemMode: 'mixed', model: _makeModel());
        break;
    }

    if (!context.mounted) return;
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
Widget _buildSystemIcon({
  required String iconPath,
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  IconData fallbackIcon = Icons.window_rounded,
}) {
  final filename = iconPath.replaceAll('\\', '/').split('/').last;
  final candidates = <String>[
    iconPath,
    if (!iconPath.startsWith('assets/')) 'assets/$iconPath',
    if (iconPath.startsWith('assets/')) iconPath.replaceFirst('assets/', ''),
    'Icon/$filename',
    'assets/Icon/$filename',
    'assets/images/$filename',
    'assets/sections/$filename',
  ].toSet().toList();

  Widget buildCandidate(int index) {
    if (index >= candidates.length) {
      return Icon(
        fallbackIcon,
        size: (width ?? height ?? 24) * 0.7,
        color: Colors.blue,
      );
    }
    return Image.asset(
      candidates[index],
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => buildCandidate(index + 1),
    );
  }

  return buildCandidate(0);
}

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
                  widget.title.contains('مختلط') ||
                  widget.title.contains('التصميم') ||
                  widget.title.toLowerCase().contains('conception'))
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
                        child: _buildSystemIcon(
                          iconPath: 'Icon/french.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: (widget.width ?? 60) * 0.65,
                        child: _buildSystemIcon(
                          iconPath: 'Icon/sli.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _buildSystemIcon(
                  iconPath: widget.iconPath,
                  width: widget.width,
                  height: widget.height,
                  fit: BoxFit.contain,
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
