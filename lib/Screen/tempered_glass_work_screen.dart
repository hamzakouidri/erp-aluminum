import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:database_data/widgets/app_material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import '../sql_database.dart';
import '../items_produits/glass_systems_rules_screen.dart';
import '../services/glass_fabrication_pdf_service.dart';
import '../Commande/glass_handle_designs.dart';
import '../Commande/tempered_glass_hardware.dart';
import '../widgets/desktop_scroll_behavior.dart';

enum GlassWorkType {
  showerCabin,
  vitrineSingleDoor,
  vitrineDoubleDoor,
  vitrineComposite,
  slidingShowerCabin,
  singleDoorShowerCabin,
}

enum SablageMode { none, full, decorative }

/// A measured horizontal glass zone.  It is deliberately stored separately
/// from the legacy decorative bands so an order can mix clear, full-frosted
/// and striped areas in one glass panel.
enum _SablageRegionType { clear, full, bands }

typedef _SablageMode = SablageMode;

enum HoleDimensionMode { edge, center }

typedef _HoleDimensionMode = HoleDimensionMode;

class TemperedGlassWorkScreen extends StatefulWidget {
  const TemperedGlassWorkScreen({
    super.key,
    this.initialPayload,
    this.allOrderGlassPayloads,
    this.clientName,
    this.orderNumber,
  });

  final Map<String, dynamic>? initialPayload;
  final List<Map<String, dynamic>>? allOrderGlassPayloads;
  final String? clientName;
  final String? orderNumber;

  static Widget buildDrawingPreview(
    Map<String, dynamic>? payload, {
    double width = 130,
    double height = 130,
  }) {
    if (payload == null) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade100,
        child: const Icon(Icons.window_rounded, color: Colors.blueGrey),
      );
    }

    final overallWidthMm =
        (payload['overallWidthMm'] as num?)?.toDouble() ??
        (payload['widthMm'] as num?)?.toDouble() ??
        1000.0;
    final overallHeightMm =
        (payload['overallHeightMm'] as num?)?.toDouble() ??
        (payload['heightMm'] as num?)?.toDouble() ??
        2000.0;

    final sablageModeStr = payload['sablageMode']?.toString() ?? 'none';
    final sablageMode = SablageMode.values.firstWhere(
      (m) => m.name == sablageModeStr,
      orElse: () => SablageMode.none,
    );
    final holeDimensionModeStr =
        payload['holeDimensionMode']?.toString() ?? 'edge';
    final holeDimensionMode = HoleDimensionMode.values.firstWhere(
      (m) => m.name == holeDimensionModeStr,
      orElse: () => HoleDimensionMode.edge,
    );

    final sablageBands = <_SablageBand>[];
    final bandsRaw = payload['sablageBands'] as List?;
    if (bandsRaw != null) {
      for (final b in bandsRaw) {
        if (b is Map) {
          sablageBands.add(
            _SablageBand(
              offsetMm: (b['offsetMm'] as num).toDouble(),
              widthMm: (b['widthMm'] as num).toDouble(),
            ),
          );
        }
      }
    }

    final panels = <_GlassPanel>[];
    final rawPanels = (payload['drawingPanels'] ?? payload['items']) as List?;
    if (rawPanels != null && rawPanels.isNotEmpty) {
      for (final p in rawPanels) {
        if (p is! Map) continue;
        final pWidthMm = (p['widthMm'] as num?)?.toDouble() ?? 500.0;
        final pHeightMm =
            (p['heightMm'] as num?)?.toDouble() ?? overallHeightMm;
        final role = p['role']?.toString() ?? 'panel';

        final holes = <_GlassHole>[];
        if (p['holes'] is List) {
          for (final h in p['holes'] as List) {
            if (h is Map) {
              holes.add(
                _GlassHole(
                  xMm: (h['xMm'] as num).toDouble(),
                  yMm: (h['yMm'] as num).toDouble(),
                  diameterMm: (h['diameterMm'] as num?)?.toDouble() ?? 20.0,
                  purpose: h['purpose']?.toString() ?? 'custom',
                ),
              );
            }
          }
        }

        Rect rect;
        if (p['left'] != null &&
            p['top'] != null &&
            p['width'] != null &&
            p['height'] != null) {
          rect = Rect.fromLTWH(
            (p['left'] as num).toDouble(),
            (p['top'] as num).toDouble(),
            (p['width'] as num).toDouble(),
            (p['height'] as num).toDouble(),
          );
        } else {
          rect = Rect.fromLTWH(0, 0, pWidthMm * 0.2, pHeightMm * 0.2);
        }

        panels.add(
          _GlassPanel(
            rect: rect,
            widthMm: pWidthMm,
            heightMm: pHeightMm,
            role: role,
            holes: holes,
          ),
        );
      }
    }

    if (panels.isEmpty) {
      panels.add(
        _GlassPanel(
          rect: const Rect.fromLTWH(55, 45, 300, 220),
          widthMm: overallWidthMm,
          heightMm: overallHeightMm,
        ),
      );
    }

    final maxRight = panels.map((p) => p.rect.right).reduce(math.max);
    final maxBottom = panels.map((p) => p.rect.bottom).reduce(math.max);
    final canvasW = math.max(maxRight + 55.0, 420.0);
    final canvasH = math.max(maxBottom + 45.0, 320.0);

    return Container(
      width: width,
      height: height,
      color: Colors.white,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: canvasW,
          height: canvasH,
          child: CustomPaint(
            painter: _GlassPanelDrawingPainter(
              panels: panels,
              draftPanel: null,
              sablageBands: sablageBands,
              draftSablageOffsetMm: null,
              sablageBandWidthMm: 40.0,
              overallHeightMm: overallHeightMm,
              overallWidthMm: overallWidthMm,
              sablageMode: sablageMode,
              zoom: 1.0,
              selectedPanelIndex: null,
              holeDimensionMode: holeDimensionMode,
              color: Colors.cyan.shade800,
            ),
          ),
        ),
      ),
    );
  }

  static Future<Uint8List> renderToPng(
    Map<String, dynamic> payload, {
    int maxSide = 1200,
    bool showHandles = true,
    bool fabricationOnly = false,
  }) async {
    final overallWidthMm =
        (payload['overallWidthMm'] as num?)?.toDouble() ??
        (payload['widthMm'] as num?)?.toDouble() ??
        1000.0;
    final overallHeightMm =
        (payload['overallHeightMm'] as num?)?.toDouble() ??
        (payload['heightMm'] as num?)?.toDouble() ??
        2000.0;

    final sablageModeStr = payload['sablageMode']?.toString() ?? 'none';
    final sablageMode = SablageMode.values.firstWhere(
      (m) => m.name == sablageModeStr,
      orElse: () => SablageMode.none,
    );
    final holeDimensionModeStr =
        payload['holeDimensionMode']?.toString() ?? 'edge';
    final holeDimensionMode = HoleDimensionMode.values.firstWhere(
      (m) => m.name == holeDimensionModeStr,
      orElse: () => HoleDimensionMode.edge,
    );

    final sablageBands = <_SablageBand>[];
    final bandsRaw = payload['sablageBands'] as List?;
    if (bandsRaw != null) {
      for (final b in bandsRaw) {
        if (b is Map) {
          sablageBands.add(
            _SablageBand(
              offsetMm: (b['offsetMm'] as num).toDouble(),
              widthMm: (b['widthMm'] as num).toDouble(),
            ),
          );
        }
      }
    }

    final sablageRegions = <_SablageRegion>[];
    final regionsRaw = payload['sablageRegions'] as List?;
    if (regionsRaw != null) {
      for (final r in regionsRaw) {
        if (r is Map) {
          sablageRegions.add(_SablageRegion.fromMap(r));
        }
      }
    }

    final panels = <_GlassPanel>[];
    final rawPanels = (payload['drawingPanels'] ?? payload['items']) as List?;
    if (rawPanels != null && rawPanels.isNotEmpty) {
      for (final p in rawPanels) {
        if (p is! Map) continue;
        final pWidthMm = (p['widthMm'] as num?)?.toDouble() ?? 500.0;
        final pHeightMm =
            (p['heightMm'] as num?)?.toDouble() ?? overallHeightMm;
        final role = p['role']?.toString() ?? 'panel';

        final holes = <_GlassHole>[];
        if (p['holes'] is List) {
          for (final h in p['holes'] as List) {
            if (h is Map) {
              holes.add(
                _GlassHole(
                  xMm: (h['xMm'] as num).toDouble(),
                  yMm: (h['yMm'] as num).toDouble(),
                  diameterMm: (h['diameterMm'] as num?)?.toDouble() ?? 20.0,
                  purpose: h['purpose']?.toString() ?? 'custom',
                ),
              );
            }
          }
        }

        Rect rect;
        if (p['left'] != null &&
            p['top'] != null &&
            p['width'] != null &&
            p['height'] != null) {
          rect = Rect.fromLTWH(
            (p['left'] as num).toDouble(),
            (p['top'] as num).toDouble(),
            (p['width'] as num).toDouble(),
            (p['height'] as num).toDouble(),
          );
        } else {
          rect = Rect.fromLTWH(0, 0, pWidthMm * 0.2, pHeightMm * 0.2);
        }

        panels.add(
          _GlassPanel(
            rect: rect,
            widthMm: pWidthMm,
            heightMm: pHeightMm,
            role: role,
            holes: holes,
          ),
        );
      }
    }

    if (panels.isEmpty) {
      panels.add(
        _GlassPanel(
          rect: const Rect.fromLTWH(55, 45, 300, 220),
          widthMm: overallWidthMm,
          heightMm: overallHeightMm,
        ),
      );
    }

    final maxRight = panels.map((p) => p.rect.right).reduce(math.max);
    final maxBottom = panels.map((p) => p.rect.bottom).reduce(math.max);
    final canvasW = math.max(maxRight + 55.0, 420.0);
    final canvasH = math.max(maxBottom + 45.0, 320.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint()..color = Colors.white,
    );

    final painter = _GlassPanelDrawingPainter(
      panels: panels,
      draftPanel: null,
      sablageBands: sablageBands,
      sablageRegions: sablageRegions,
      draftSablageOffsetMm: null,
      sablageBandWidthMm: 40.0,
      overallHeightMm: overallHeightMm,
      overallWidthMm: overallWidthMm,
      sablageMode: sablageMode,
      zoom: 1.0,
      selectedPanelIndex: null,
      holeDimensionMode: holeDimensionMode,
      color: Colors.cyan.shade800,
      showHandles: showHandles,
      fabricationOnly: fabricationOnly,
      showSlidingProfiles:
          payload['slidingRule'] != null && payload['showProfiles'] != false,
      dimensionReferenceLabel:
          payload['holeDimensionModeLabel']?.toString() ??
          (payload['holeDimensionMode'] == 'center'
              ? "Cotes des trous : à l'axe du trou"
              : 'Cotes des trous : au bord du trou'),
      gasketEdges: {
        if (payload['gasketItems'] is Map)
          for (final e in (payload['gasketItems'] as Map).entries)
            if ((e.value as num?) != null && (e.value as num) > 0)
              e.key.toString(),
      },
    );

    painter.paint(canvas, Size(canvasW, canvasH));
    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasW.round(), canvasH.round());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  @override
  State<TemperedGlassWorkScreen> createState() =>
      _TemperedGlassWorkScreenState();
}

class _TemperedGlassWorkScreenState extends State<TemperedGlassWorkScreen> {
  final ScrollController _toolbarScrollController = ScrollController();
  final ScrollController _appBarActionsScrollController = ScrollController();
  // Initial workshop values. Keep these in one place so they can later be
  // moved to the workshop settings screen without changing the drawing code.
  static const _defaultHoleDiameterMm = 20.0;
  static const _defaultDoorHeightIncreaseMm = 30.0;
  static const _defaultFixedWidthIncreaseMm = 30.0;
  static const _freehandMaxWidthMm = 3000.0;
  static const _freehandMaxHeightMm = 3500.0;
  static const _slidingVisualGapPx = 2.0;
  double _doorTopHoleSideOffsetMm = 80.0;
  double _doorTopHoleTopOffsetMm = 35.0;
  // 54 mm to the hole centre keeps a Ø20 handle hole at least 44 mm from glass.
  static const _handleHoleEdgeOffsetMm = 54.0;
  static const _handleHoleSpacingMm = 200.0;
  static const _towelHoleSpacingMm = 450.0;

  bool _showDoorHandle = true;
  bool _showTowelHandle = true;
  String _selectedHandleShape = 'round';
  String _selectedHandleDesignCode = 'vro_ronde';

  GlassWorkType _workType = GlassWorkType.vitrineSingleDoor;
  final List<_GlassPanel> _panels = [];
  final Map<String, _HoleOverride> _holeOverrides = {};
  int? _selectedPanelIndex;
  final _doorWidthController = TextEditingController(text: '800');
  bool _doorWidthCustomized = false;
  final _sablageBandWidthController = TextEditingController(text: '40');
  final _sablageTransparentWidthController = TextEditingController(text: '40');
  final _sablageCountController = TextEditingController(text: '3');
  final _sablageStartController = TextEditingController(text: '0');
  final _sablageEndController = TextEditingController(text: '400');
  final List<_SablageBand> _sablageBands = [];
  final List<_SablageRegion> _sablageRegions = [];
  Rect? _overallDrawingRect;
  double? _overallWidthMmValue;
  double? _overallHeightMmValue;
  Offset? _drawStart;
  Rect? _draftPanel;
  double? _draftSablageOffsetMm;
  int? _draggingPanelIndex;
  double _handleEdgeOffsetMm = _handleHoleEdgeOffsetMm;
  double _handleSpacingMm = _handleHoleSpacingMm;
  double _holeDiameterMm = _defaultHoleDiameterMm;
  double? _handleCenterFromTopMm;
  double? _towelCenterFromLeftMm;
  double? _towelCenterFromTopMm;
  double _towelSpacingMm = _towelHoleSpacingMm;
  _MovableHoleTarget? _draggingHole;
  double _zoom = 1.0;
  Size _canvasSize = Size.zero;
  final List<_GlassDrawingSnapshot> _undoStack = [];
  final List<_GlassDrawingSnapshot> _redoStack = [];
  _SablageMode _sablageMode = _SablageMode.none;
  bool _sablageRangeMode = false;
  bool _sablageFromBottom = false;
  bool _sablageDrawingActive = false;
  double _glassThicknessMm = 10.0;
  String _glassType = 'شفاف';
  bool _glassTempered = true;
  String _edgeFinish = 'smooth';
  bool _doorOnLeft = true;
  _HoleDimensionMode _holeDimensionMode = _HoleDimensionMode.edge;
  bool _initialPayloadRestored = false;
  bool _sideToolbarExpanded = true;
  final SqlDatabase _db = SqlDatabase();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _catalogAccessories = [];
  Map<int, int> _selectedAccessories = {};
  String _accDrawerCategory = 'all';
  String _accDrawerSearch = '';

  List<Map<String, dynamic>> _glassKits = [];
  Map<String, dynamic>? _selectedKit;

  /// The user chose to draw without a kit (free drawing). Without this the
  /// default kit would be selected again on the next catalogue load.
  bool _noKit = false;

  /// Kit saved with the order being reopened.
  int? _initialKitId;

  /// Show the U channel and top rail of a sliding shower on the drawing.
  bool _showProfiles = true;

  /// Profile chosen for each [GlassProfileRole]; 0 means none. A role
  /// without an entry uses the first catalogue profile of that role made
  /// for the glass thickness.
  final Map<String, int> _profileItems = {};

  /// Gasket chosen for each [GlassGasketLocation].
  final Map<String, int> _gasketItems = {};

  /// Colour of the hardware (handles, hinges, profiles, gaskets...); each
  /// accessory is priced in this colour when it has a price for it.
  String _hardwareColor = '';

  double _colorPrice(Map<String, dynamic> item, double fallback) =>
      item['price'] is num
      ? glassItemPriceForColor(item, _hardwareColor)
      : fallback;

  /// Every colour some catalogue accessory has a price for.
  List<String> get _hardwareColors {
    final colors = <String, String>{};
    for (final item in _catalogAccessories) {
      for (final entry in parseColorPrices(item['color_prices'])) {
        colors.putIfAbsent(entry.color.toLowerCase(), () => entry.color);
      }
    }
    return colors.values.toList()..sort();
  }

  /// A kit fixes the drillings, hinges and accessories of its glass: nothing
  /// can be added to it, moved or removed. Free drawing (no kit) allows it.
  bool get _kitLocked => _selectedKit != null;

  /// Shows why a change is refused while a kit is applied. Returns true when
  /// the change must stop.
  bool _refuseWhenKitLocked() {
    if (!_kitLocked) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'الكيت المطبَّق يحدد الثقوب والمفاصل والإكسسوارات، ولا يقبل أي إضافة أو تعديل عليها. اختر «بدون كيت» للرسم الحر.',
              'Le kit appliqué fixe les perçages, charnières et accessoires : aucun ajout ni modification n\'est accepté. Choisissez « Sans kit » pour un dessin libre.',
              'The applied kit fixes the holes, hinges and accessories: nothing can be added or changed. Choose "No kit" to draw freely.',
            ),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    return true;
  }
  List<Map<String, dynamic>> _activeKitHoles = [];
  List<Map<String, dynamic>> _activeKitComponents = [];
  List<Map<String, dynamic>> _systemRules = [];
  List<Map<String, dynamic>> _glassSystems = [];
  String? _selectedSystemCode;

  String get _currentSystemCode {
    if (_selectedSystemCode != null && _selectedSystemCode!.isNotEmpty) {
      return _selectedSystemCode!;
    }
    return switch (_workType) {
      GlassWorkType.slidingShowerCabin => 'coulissante',
      GlassWorkType.showerCabin => 'cabine_l',
      GlassWorkType.singleDoorShowerCabin => 'cabine_porte',
      GlassWorkType.vitrineSingleDoor => 'vitrine_1p',
      GlassWorkType.vitrineDoubleDoor => 'vitrine_2p',
      GlassWorkType.vitrineComposite => 'vitrine_composite_5p',
    };
  }

  String get _currentSystemName {
    if (_selectedSystemCode != null && _glassSystems.isNotEmpty) {
      final sys = _glassSystems.firstWhere(
        (s) => s['code'] == _selectedSystemCode,
        orElse: () => <String, dynamic>{},
      );
      if (sys.isNotEmpty) {
        final lang = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).language;
        if (lang == AppLanguage.french &&
            (sys['name_fr'] ?? '').toString().isNotEmpty) {
          return sys['name_fr'];
        }
        if (lang == AppLanguage.english &&
            (sys['name_en'] ?? '').toString().isNotEmpty) {
          return sys['name_en'];
        }
        return sys['name_ar'] ?? sys['code'];
      }
    }
    return _workTypeLabel(_workType);
  }

  GlassWorkType _mapCodeToWorkType(String code) {
    if (code == 'coulissante' || code.contains('couliss')) {
      return GlassWorkType.slidingShowerCabin;
    }
    if (code == 'cabine_l' || code == 'cabine_u') {
      return GlassWorkType.showerCabin;
    }
    if (code == 'vitrine_composite_5p' || code.contains('composite')) {
      return GlassWorkType.vitrineComposite;
    }
    if (code == 'vitrine_2p' || code.contains('double')) {
      return GlassWorkType.vitrineDoubleDoor;
    }
    if (code == 'vitrine_1p') {
      return GlassWorkType.vitrineSingleDoor;
    }
    if (code == 'cabine_porte' ||
        code == 'cabine_fixe_porte' ||
        code == 'paroi_fixe') {
      return GlassWorkType.singleDoorShowerCabin;
    }
    return GlassWorkType.singleDoorShowerCabin;
  }

  Future<void> _selectSystem(Map<String, dynamic> sys) async {
    final code = (sys['code'] ?? '').toString();
    final mappedType = _mapCodeToWorkType(code);
    _selectedSystemCode = code;

    final defaultKitCode = (sys['default_kit_code'] as String?)?.trim() ?? '';
    if (defaultKitCode.isNotEmpty && _glassKits.isNotEmpty) {
      final matchingKit = _glassKits.firstWhere(
        (k) => k['code'] == defaultKitCode,
        orElse: () => <String, dynamic>{},
      );
      if (matchingKit.isNotEmpty) {
        _selectedKit = matchingKit;
        _noKit = false;
        await _loadKitHoles(matchingKit['id'] as int);
      }
    }

    await _loadSystemRules();
    _applySelectedWorkType(mappedType);
  }

  @override
  void initState() {
    super.initState();
    _applyInitialPayloadSettings();
    _loadAccessories();
  }

  @override
  void dispose() {
    _toolbarScrollController.dispose();
    _appBarActionsScrollController.dispose();
    _doorWidthController.dispose();
    _sablageBandWidthController.dispose();
    _sablageTransparentWidthController.dispose();
    _sablageCountController.dispose();
    _sablageStartController.dispose();
    _sablageEndController.dispose();
    super.dispose();
  }

  Future<void> _loadAccessories() async {
    try {
      await _db.ensureTemperedGlassSystemsAndRulesTables();
      final items = await _db.getTemperedGlassItems();
      final kits = await _db.getTemperedGlassKits(onlyActive: true);
      final systems = await _db.getTemperedGlassSystems(onlyActive: true);
      if (mounted) {
        setState(() {
          _catalogAccessories = items;
          _glassKits = kits;
          _glassSystems = systems;
          final initialKit = _initialKitId == null
              ? null
              : kits.where((k) => k['id'] == _initialKitId).firstOrNull;
          _initialKitId = null;
          if (initialKit != null) {
            _selectedKit = initialKit;
          } else if (_selectedKit == null && !_noKit && kits.isNotEmpty) {
            _selectedKit = kits.firstWhere(
              (k) => k['code'] == 'kit_alfa',
              orElse: () => kits.first,
            );
          }
        });
        if (_selectedKit != null) {
          await _loadKitHoles(_selectedKit!['id'] as int);
        }
        await _loadSystemRules();
      }
    } catch (_) {}
  }

  Future<void> _loadKitHoles(int kitId) async {
    try {
      final results = await Future.wait([
        _db.getTemperedGlassKitHoles(kitId),
        _db.getTemperedGlassKitComponents(kitId),
      ]);
      final holes = results[0];
      final components = results[1];
      if (mounted) {
        setState(() {
          _activeKitHoles = holes;
          _activeKitComponents = components;
          final allowedIds = components
              .map((row) => (row['item_id'] as num?)?.toInt())
              .whereType<int>()
              .toSet();
          if (allowedIds.isNotEmpty) {
            _selectedAccessories.removeWhere(
              (itemId, _) => !allowedIds.contains(itemId),
            );
          }
        });
        if (_isSlidingStraight) {
          _applySlidingLayout();
        } else {
          _updatePanelsForHandles();
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSystemRules() async {
    try {
      final code = _currentSystemCode;
      final rules = await _db.getTemperedGlassSystemRules(
        code,
        glassThicknessMm: _glassThicknessMm,
      );
      if (mounted) {
        setState(() => _systemRules = rules);
      }
    } catch (_) {}
  }

  Future<void> _showKitSelectionDialog() async {
    final kits = await _db.getTemperedGlassKits(onlyActive: true);
    if (!mounted) return;
    setState(() => _glassKits = kits);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.architecture_outlined, color: Colors.cyan),
            const SizedBox(width: 8),
            Text(
              _tr(
                'اختيار كيت الزجاج وقواعد الثقوب',
                'Choisir le kit verre',
                'Choose Glass Kit',
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr(
                    'الكيت يحدد أبعاد وقواعد ثقوب الرولمان في الباب، المسافات من الحواف، والأقطار تلقائياً:',
                    'Le kit définit les perçages des roulettes, décalages et diamètres :',
                    'The kit defines door roller drillings, edge offsets, and hole diameters:',
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (kits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _tr(
                        'لا توجد كيتات مضافة',
                        'Aucun kit disponible',
                        'No kits available',
                      ),
                    ),
                  )
                else
                  ...kits.map((kit) {
                    final isSelected = _selectedKit?['id'] == kit['id'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? Colors.cyan
                              : Colors.grey.withValues(alpha: 0.3),
                          width: isSelected ? 2 : 1,
                        ),
                        color: isSelected
                            ? Colors.cyan.withValues(alpha: 0.08)
                            : null,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? Colors.cyan.shade700
                              : Colors.blueGrey.shade100,
                          foregroundColor: isSelected
                              ? Colors.white
                              : Colors.black87,
                          child: const Icon(Icons.hardware, size: 20),
                        ),
                        title: Text(
                          kit['name'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          kit['description'] as String? ?? '',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.cyan)
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          setState(() {
                            _selectedKit = kit;
                            _noKit = false;
                          });
                          await _loadKitHoles(kit['id'] as int);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_tr('تم تطبيق كيت', 'Kit appliqué :', 'Applied kit:')} ${kit['name']}',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedKit == null
                          ? Colors.cyan
                          : Colors.grey.withValues(alpha: 0.3),
                      width: _selectedKit == null ? 2 : 1,
                    ),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.draw_outlined, size: 20),
                    ),
                    title: Text(
                      _tr('بدون كيت (رسم حر)', 'Sans kit (dessin libre)',
                          'No kit (free drawing)'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      _tr(
                        'تضيف الثقوب والمفاصل والإكسسوارات بنفسك.',
                        'Vous ajoutez vous-même perçages, charnières et accessoires.',
                        'You add the holes, hinges and accessories yourself.',
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: _selectedKit == null
                        ? const Icon(Icons.check_circle, color: Colors.cyan)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _selectedKit = null;
                        _noKit = true;
                        _activeKitHoles = [];
                        _activeKitComponents = [];
                      });
                      if (_isSlidingStraight) {
                        _applySlidingLayout();
                      } else {
                        _updatePanelsForHandles();
                      }
                    },
                  ),
                ),
                const Divider(),
                TextButton.icon(
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(
                    _tr(
                      'إدارة وتعديل قواعد وأنظمة الكيت...',
                      'Gérer systèmes & kits...',
                      'Manage Systems & Kits...',
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GlassSystemsRulesScreen(db: _db),
                      ),
                    );
                    _loadAccessories();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applyInitialPayloadSettings() {
    final payload = widget.initialPayload;
    if (payload == null) return;

    final workTypeStr = payload['workType']?.toString();
    if (workTypeStr != null) {
      _workType = GlassWorkType.values.firstWhere(
        (t) => t.name == workTypeStr,
        orElse: () => GlassWorkType.vitrineSingleDoor,
      );
    }

    final sysCode = payload['systemCode']?.toString();
    if (sysCode != null && sysCode.isNotEmpty) {
      _selectedSystemCode = sysCode;
    }

    if (payload.containsKey('kitId')) {
      _initialKitId = (payload['kitId'] as num?)?.toInt();
      _noKit = _initialKitId == null;
    }

    final holeDimensionModeStr = payload['holeDimensionMode']?.toString();
    if (holeDimensionModeStr != null) {
      _holeDimensionMode = HoleDimensionMode.values.firstWhere(
        (m) => m.name == holeDimensionModeStr,
        orElse: () => HoleDimensionMode.edge,
      );
    }

    _glassType = payload['glassType']?.toString() ?? 'شفاف';
    _glassTempered = payload['glassTempered'] != false;
    final loadedFinish = payload['edgeFinish']?.toString() ?? 'smooth';
    _edgeFinish = (loadedFinish == 'extra_smooth') ? 'extra_smooth' : 'smooth';
    final accRaw = payload['selectedAccessories'];
    if (accRaw is Map) {
      _selectedAccessories = accRaw.map(
        (k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, (v as num).toInt()),
      )..remove(0);
    }
    _glassThicknessMm =
        (payload['glassThicknessMm'] ?? payload['thicknessMm'] as num?)
            ?.toDouble() ??
        10.0;
    _showProfiles = payload['showProfiles'] != false;
    _hardwareColor = payload['hardwareColor']?.toString() ?? '';
    for (final entry in [
      (payload['profileItems'], _profileItems),
      (payload['gasketItems'], _gasketItems),
    ]) {
      final raw = entry.$1;
      if (raw is Map) {
        for (final e in raw.entries) {
          final id = (e.value as num?)?.toInt();
          if (id != null) entry.$2[e.key.toString()] = id;
        }
      }
    }
    _overallWidthMmValue =
        (payload['overallWidthMm'] ?? payload['widthMm'] as num?)?.toDouble();
    _overallHeightMmValue =
        (payload['overallHeightMm'] ?? payload['heightMm'] as num?)?.toDouble();

    final sablageModeStr = payload['sablageMode']?.toString() ?? 'none';
    _sablageMode = SablageMode.values.firstWhere(
      (m) => m.name == sablageModeStr,
      orElse: () => SablageMode.none,
    );

    _sablageBands.clear();
    final bandsRaw = payload['sablageBands'] as List?;
    if (bandsRaw != null) {
      for (final b in bandsRaw) {
        if (b is Map) {
          _sablageBands.add(
            _SablageBand(
              offsetMm: (b['offsetMm'] as num).toDouble(),
              widthMm: (b['widthMm'] as num).toDouble(),
            ),
          );
        }
      }
    }
    _sablageRegions.clear();
    final regionsRaw = payload['sablageRegions'] as List?;
    if (regionsRaw != null) {
      for (final region in regionsRaw) {
        if (region is Map) _sablageRegions.add(_SablageRegion.fromMap(region));
      }
    }

    if (payload['slidingRule'] is Map) {
      final sr = payload['slidingRule'] as Map;
      final doorW = (sr['doorWidthMm'] as num?)?.toDouble();
      if (doorW != null) {
        _doorWidthController.text = doorW.toStringAsFixed(0);
        _doorWidthCustomized = true;
      }
      if (sr['doorOnLeft'] != null) {
        _doorOnLeft = sr['doorOnLeft'] == true;
      }
    }
  }

  void _restoreDrawingFromInitialPayload(Size canvasSize) {
    if (_initialPayloadRestored || widget.initialPayload == null) return;
    _initialPayloadRestored = true;

    final payload = widget.initialPayload!;
    final overallW = _overallWidthMmValue ?? 1000.0;
    final overallH = _overallHeightMmValue ?? 2000.0;

    if (_isSlidingStraight) {
      _overallDrawingRect = _rectForMeasurement(overallW, overallH);
      _applySlidingLayout();
      return;
    }

    final rawPanels = (payload['drawingPanels'] ?? payload['items']) as List?;
    if (rawPanels != null && rawPanels.isNotEmpty) {
      _panels.clear();
      for (final p in rawPanels) {
        if (p is! Map) continue;
        final pWidthMm = (p['widthMm'] as num?)?.toDouble() ?? 500.0;
        final pHeightMm = (p['heightMm'] as num?)?.toDouble() ?? overallH;
        final role = p['role']?.toString() ?? 'panel';

        final holes = <_GlassHole>[];
        if (p['holes'] is List) {
          for (final h in p['holes'] as List) {
            if (h is Map) {
              holes.add(
                _GlassHole(
                  xMm: (h['xMm'] as num).toDouble(),
                  yMm: (h['yMm'] as num).toDouble(),
                  diameterMm: (h['diameterMm'] as num?)?.toDouble() ?? 20.0,
                  purpose: h['purpose']?.toString() ?? 'custom',
                ),
              );
            }
          }
        }

        final hinges = <_GlassHinge>[];
        if (p['hinges'] is List) {
          for (final h in p['hinges'] as List) {
            if (h is Map) {
              hinges.add(_GlassHinge.fromMap(h));
            }
          }
        }

        Rect rect;
        if (p['left'] != null &&
            p['top'] != null &&
            p['width'] != null &&
            p['height'] != null) {
          rect = Rect.fromLTWH(
            (p['left'] as num).toDouble(),
            (p['top'] as num).toDouble(),
            (p['width'] as num).toDouble(),
            (p['height'] as num).toDouble(),
          );
        } else {
          rect = _rectForMeasurement(pWidthMm, pHeightMm);
        }

        _panels.add(
          _GlassPanel(
            rect: rect,
            widthMm: pWidthMm,
            heightMm: pHeightMm,
            role: role,
            holes: holes,
            hinges: hinges,
          ),
        );
      }
      if (_panels.isNotEmpty) {
        _selectedPanelIndex = 0;
      }
    }
  }

  bool get _isSlidingStraight => _workType == GlassWorkType.slidingShowerCabin;

  bool _isCompactLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 700.0;

  String _edgeFinishLabel(String value) {
    return switch (value) {
      'extra_smooth' => _tr('ناعم جداً', 'Très poli', 'Extra smooth'),
      _ => _tr('ناعم', 'Poli', 'Smooth'),
    };
  }

  /// Where every hole distance on the drawing and the sheets is measured.
  String _holeDimensionReferenceLabel() =>
      _holeDimensionMode == _HoleDimensionMode.center
      ? _tr(
          'أبعاد الثقوب: من مركز الثقب',
          "Cotes des trous : à l'axe du trou",
          'Hole distances: to the hole centre',
        )
      : _tr(
          'أبعاد الثقوب: من حافة الثقب',
          'Cotes des trous : au bord du trou',
          'Hole distances: to the hole edge',
        );

  String _glassTypeLabel(String value) {
    return switch (value) {
      'شفاف' => _tr('شفاف', 'Transparent', 'Clear'),
      'ملون' => _tr('ملون', 'Teinté', 'Tinted'),
      'عاكس' => _tr('عاكس', 'Réfléchissant', 'Reflective'),
      'مصفح' => _tr('مصفح', 'Feuilleté', 'Laminated'),
      'معتّم' => _tr('معتّم', 'Opaque', 'Opaque'),
      'شفاف إضافي' => _tr('شفاف إضافي', 'Extra-clair', 'Extra clear'),
      'ساتان' => _tr('ساتان (مثلّج)', 'Satiné', 'Satin (acid-etched)'),
      'مطبوع' => _tr('مطبوع', 'Imprimé', 'Patterned'),
      'mirror' => _tr('زجاج مرآة', 'Verre miroir', 'Mirror glass'),
      _ => _tr('زجاج عادي', 'Verre normal', 'Standard glass'),
    };
  }

  Offset _canvasPosition(Offset screenPosition) {
    if (_canvasSize == Size.zero || _zoom == 1.0) return screenPosition;
    final center = _canvasSize.center(Offset.zero);
    return (screenPosition - center) / _zoom + center;
  }

  void _pushHistory() {
    _undoStack.add(
      _GlassDrawingSnapshot.capture(
        panels: _panels,
        overallDrawingRect: _overallDrawingRect,
        overallWidthMm: _overallWidthMmValue,
        overallHeightMm: _overallHeightMmValue,
        sablageBands: _sablageBands,
        workType: _workType,
        handleEdgeOffsetMm: _handleEdgeOffsetMm,
        handleSpacingMm: _handleSpacingMm,
        handleCenterFromTopMm: _handleCenterFromTopMm,
        towelCenterFromLeftMm: _towelCenterFromLeftMm,
        towelCenterFromTopMm: _towelCenterFromTopMm,
        towelSpacingMm: _towelSpacingMm,
        doorTopHoleSideOffsetMm: _doorTopHoleSideOffsetMm,
        doorTopHoleTopOffsetMm: _doorTopHoleTopOffsetMm,
        showDoorHandle: _showDoorHandle,
        showTowelHandle: _showTowelHandle,
        holeDiameterMm: _holeDiameterMm,
        holeOverrides: _holeOverrides,
        sablageMode: _sablageMode,
        sablageRangeMode: _sablageRangeMode,
        sablageFromBottom: _sablageFromBottom,
        glassThicknessMm: _glassThicknessMm,
        doorOnLeft: _doorOnLeft,
        holeDimensionMode: _holeDimensionMode,
        edgeFinish: _edgeFinish,
        selectedAccessories: Map<int, int>.from(_selectedAccessories),
      ),
    );
    _redoStack.clear();
  }

  void _restoreSnapshot(_GlassDrawingSnapshot snapshot) {
    _panels
      ..clear()
      ..addAll(snapshot.panels.map((panel) => panel.copy()));
    _overallDrawingRect = snapshot.overallDrawingRect;
    _overallWidthMmValue = snapshot.overallWidthMm;
    _overallHeightMmValue = snapshot.overallHeightMm;
    _sablageBands
      ..clear()
      ..addAll(snapshot.sablageBands);
    _workType = snapshot.workType;
    _handleEdgeOffsetMm = snapshot.handleEdgeOffsetMm;
    _handleSpacingMm = snapshot.handleSpacingMm;
    _handleCenterFromTopMm = snapshot.handleCenterFromTopMm;
    _towelCenterFromLeftMm = snapshot.towelCenterFromLeftMm;
    _towelCenterFromTopMm = snapshot.towelCenterFromTopMm;
    _towelSpacingMm = snapshot.towelSpacingMm;
    _doorTopHoleSideOffsetMm = snapshot.doorTopHoleSideOffsetMm;
    _doorTopHoleTopOffsetMm = snapshot.doorTopHoleTopOffsetMm;
    _showDoorHandle = snapshot.showDoorHandle;
    _showTowelHandle = snapshot.showTowelHandle;
    _holeDiameterMm = snapshot.holeDiameterMm;
    _holeOverrides
      ..clear()
      ..addAll(
        snapshot.holeOverrides.map((key, value) => MapEntry(key, value.copy())),
      );
    _sablageMode = snapshot.sablageMode;
    _sablageRangeMode = snapshot.sablageRangeMode;
    _sablageFromBottom = snapshot.sablageFromBottom;
    _glassThicknessMm = snapshot.glassThicknessMm;
    _doorOnLeft = snapshot.doorOnLeft;
    _holeDimensionMode = snapshot.holeDimensionMode;
    _edgeFinish = snapshot.edgeFinish;
    _selectedAccessories = Map<int, int>.from(snapshot.selectedAccessories);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(
        _GlassDrawingSnapshot.capture(
          panels: _panels,
          overallDrawingRect: _overallDrawingRect,
          overallWidthMm: _overallWidthMmValue,
          overallHeightMm: _overallHeightMmValue,
          sablageBands: _sablageBands,
          workType: _workType,
          handleEdgeOffsetMm: _handleEdgeOffsetMm,
          handleSpacingMm: _handleSpacingMm,
          handleCenterFromTopMm: _handleCenterFromTopMm,
          towelCenterFromLeftMm: _towelCenterFromLeftMm,
          towelCenterFromTopMm: _towelCenterFromTopMm,
          towelSpacingMm: _towelSpacingMm,
          doorTopHoleSideOffsetMm: _doorTopHoleSideOffsetMm,
          doorTopHoleTopOffsetMm: _doorTopHoleTopOffsetMm,
          showDoorHandle: _showDoorHandle,
          showTowelHandle: _showTowelHandle,
          holeDiameterMm: _holeDiameterMm,
          holeOverrides: _holeOverrides,
          sablageMode: _sablageMode,
          sablageRangeMode: _sablageRangeMode,
          sablageFromBottom: _sablageFromBottom,
          glassThicknessMm: _glassThicknessMm,
          doorOnLeft: _doorOnLeft,
          holeDimensionMode: _holeDimensionMode,
          edgeFinish: _edgeFinish,
          selectedAccessories: Map<int, int>.from(_selectedAccessories),
        ),
      );
      _restoreSnapshot(_undoStack.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(
        _GlassDrawingSnapshot.capture(
          panels: _panels,
          overallDrawingRect: _overallDrawingRect,
          overallWidthMm: _overallWidthMmValue,
          overallHeightMm: _overallHeightMmValue,
          sablageBands: _sablageBands,
          workType: _workType,
          handleEdgeOffsetMm: _handleEdgeOffsetMm,
          handleSpacingMm: _handleSpacingMm,
          handleCenterFromTopMm: _handleCenterFromTopMm,
          towelCenterFromLeftMm: _towelCenterFromLeftMm,
          towelCenterFromTopMm: _towelCenterFromTopMm,
          towelSpacingMm: _towelSpacingMm,
          doorTopHoleSideOffsetMm: _doorTopHoleSideOffsetMm,
          doorTopHoleTopOffsetMm: _doorTopHoleTopOffsetMm,
          showDoorHandle: _showDoorHandle,
          showTowelHandle: _showTowelHandle,
          holeDiameterMm: _holeDiameterMm,
          holeOverrides: _holeOverrides,
          sablageMode: _sablageMode,
          sablageRangeMode: _sablageRangeMode,
          sablageFromBottom: _sablageFromBottom,
          glassThicknessMm: _glassThicknessMm,
          doorOnLeft: _doorOnLeft,
          holeDimensionMode: _holeDimensionMode,
          edgeFinish: _edgeFinish,
          selectedAccessories: Map<int, int>.from(_selectedAccessories),
        ),
      );
      _restoreSnapshot(_redoStack.removeLast());
    });
  }

  void _changeZoom(double delta) {
    setState(() => _zoom = (_zoom + delta).clamp(0.5, 2.5).toDouble());
  }

  void _toggleSlidingSides() {
    if (!_isSlidingStraight || _overallDrawingRect == null) return;
    _pushHistory();
    setState(() {
      final previousDoor = _panels
          .where((panel) => panel.isDoor)
          .firstOrNull
          ?.copy();
      final previousFixed = _panels
          .where((panel) => !panel.isDoor)
          .firstOrNull
          ?.copy();
      _doorOnLeft = !_doorOnLeft;
      _applySlidingLayout();

      void restorePanelComponents(_GlassPanel target, _GlassPanel? source) {
        if (source == null) return;
        target.holes = source.holes
            .map(
              (hole) => _GlassHole(
                xMm: (target.widthMm - hole.xMm)
                    .clamp(0.0, target.widthMm)
                    .toDouble(),
                yMm: hole.yMm.clamp(0.0, target.heightMm).toDouble(),
                diameterMm: hole.diameterMm,
                purpose: hole.purpose,
              ),
            )
            .toList();
        target.hinges = source.hinges
            .map(
              (hinge) => _GlassHinge(
                yMm: hinge.yMm.clamp(0.0, target.heightMm).toDouble(),
                side: hinge.side == 'left' ? 'right' : 'left',
                widthMm: hinge.widthMm,
                heightMm: hinge.heightMm,
              ),
            )
            .toList();
      }

      final currentDoor = _panels.where((panel) => panel.isDoor).firstOrNull;
      final currentFixed = _panels.where((panel) => !panel.isDoor).firstOrNull;
      if (currentDoor != null)
        restorePanelComponents(currentDoor, previousDoor);
      if (currentFixed != null) {
        restorePanelComponents(currentFixed, previousFixed);
      }
    });
  }

  /// Swap panel layout horizontally (Inverser l'ordre des panneaux ⇄)
  void _swapPanelsOrder() {
    if (_panels.length < 2) return;
    _pushHistory();
    setState(() {
      // If sliding cabin, reuse specialized sliding flip
      if (_isSlidingStraight) {
        _toggleSlidingSides();
        return;
      }

      // Check if there is an imposte (transom) on top
      final imposte = _panels.where((p) => p.role.contains('imposte')).firstOrNull;
      final bottomPanels = _panels.where((p) => !p.role.contains('imposte')).toList();

      if (bottomPanels.length < 2) return;

      // Reverse bottom panels order horizontally
      final minLeft = bottomPanels.map((p) => p.rect.left).reduce(math.min);
      final maxRight = bottomPanels.map((p) => p.rect.right).reduce(math.max);
      final totalWidth = maxRight - minLeft;

      final reversed = bottomPanels.reversed.toList();
      double curX = minLeft;
      for (final panel in reversed) {
        final w = panel.rect.width;
        final h = panel.rect.height;
        final t = panel.rect.top;
        panel.rect = Rect.fromLTWH(curX, t, w, h);
        curX += w + 3.0;

        // Invert horizontal hole positions
        for (final hole in panel.holes) {
          hole.xMm = (panel.widthMm - hole.xMm).clamp(0.0, panel.widthMm);
        }
        // Invert hinge sides
        for (final hinge in panel.hinges) {
          hinge.side = hinge.side == 'left' ? 'right' : 'left';
        }
      }

      _panels.clear();
      _panels.addAll(reversed);
      if (imposte != null) _panels.add(imposte);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'تم قلب ترتيب الألواح وتحديث الإحداثيات بنجاح',
            'Ordre des panneaux inversé avec succès',
            'Panels order inverted successfully',
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Toggle hinge side and synchronize notches between Door and adjacent panel
  void _toggleHingeSide() {
    // Find the currently selected panel or the first door
    _GlassPanel? targetDoor;
    if (_selectedPanelIndex != null &&
        _selectedPanelIndex! >= 0 &&
        _selectedPanelIndex! < _panels.length) {
      final sel = _panels[_selectedPanelIndex!];
      if (sel.isDoor) targetDoor = sel;
    }
    targetDoor ??= _panels.where((p) => p.isDoor).firstOrNull;

    if (targetDoor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'يرجى تحديد لوح باب لتغيير جهة المفصلات',
              'Sélectionnez une porte pour changer le côté des charnières',
              'Select a door to change hinge side',
            ),
          ),
        ),
      );
      return;
    }

    _pushHistory();
    setState(() {
      // Toggle hinges side
      final oldSide = targetDoor!.hinges.isNotEmpty ? targetDoor.hinges.first.side : 'left';
      final newSide = oldSide == 'left' ? 'right' : 'left';

      // Determine adjacent panel on newSide
      _GlassPanel? adjacentPanel;
      if (newSide == 'left') {
        adjacentPanel = _panels
            .where((p) => p != targetDoor && p.rect.right <= targetDoor!.rect.left + 15 && !p.role.contains('imposte'))
            .firstOrNull;
      } else {
        adjacentPanel = _panels
            .where((p) => p != targetDoor && p.rect.left >= targetDoor!.rect.right - 15 && !p.role.contains('imposte'))
            .firstOrNull;
      }

      final isAdjacentToGlass = adjacentPanel != null;
      final hingeType = isAdjacentToGlass ? 'glass_glass_180' : 'wall_glass';

      // Clear any prior matching hinges from adjacent panel
      for (final p in _panels) {
        if (!p.isDoor) {
          p.hinges.removeWhere((h) => h.hingeType == 'glass_glass_180');
        }
      }

      if (targetDoor.hinges.isEmpty) {
        targetDoor.ensureDoorHinges(hingeSide: newSide);
      } else {
        for (final h in targetDoor.hinges) {
          h.side = newSide;
          h.hingeType = hingeType;
        }
      }

      // If hinged to adjacent glass panel, add synchronized notches / hinges to adjacent fixed panel
      if (adjacentPanel != null) {
        final adjHingeSide = newSide == 'left' ? 'right' : 'left';
        adjacentPanel.hinges.clear();
        for (final doorHinge in targetDoor.hinges) {
          adjacentPanel.hinges.add(
            _GlassHinge(
              yMm: doorHinge.yMm.clamp(0.0, adjacentPanel.heightMm),
              side: adjHingeSide,
              widthMm: doorHinge.widthMm,
              heightMm: doorHinge.heightMm,
              hingeType: 'glass_glass_180',
            ),
          );
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'تم تبديل جهة المفصلات وتحديث تفريغات الزجاج المتزامنة',
            'Côté des charnières modifié (encoches synchronisées)',
            'Hinge side changed with synchronized glass notches',
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _tr(String ar, String fr, String en) {
    final language = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return switch (language) {
      AppLanguage.arabic => ar,
      AppLanguage.french => fr,
      AppLanguage.english => en,
    };
  }

  String _workTypeLabel(GlassWorkType type) {
    return switch (type) {
      GlassWorkType.showerCabin => _tr(
        'كابين دوش',
        'Cabine de douche',
        'Shower cabin',
      ),
      GlassWorkType.vitrineSingleDoor => _tr(
        'فيترين بباب واحد',
        'Vitrine à une porte',
        'One-door storefront',
      ),
      GlassWorkType.vitrineDoubleDoor => _tr(
        'فيترين ببابين',
        'Vitrine à deux portes',
        'Two-door storefront',
      ),
      GlassWorkType.slidingShowerCabin => _tr(
        'كابين دوش منزلقة',
        'Cabine de douche coulissante',
        'Sliding shower cabin',
      ),
      GlassWorkType.singleDoorShowerCabin => _tr(
        'كابين دوش بباب واحد',
        'Cabine de douche à une porte',
        'One-door shower cabin',
      ),
      GlassWorkType.vitrineComposite => _tr(
        'فيترين مجمعة (5 ألواح)',
        'Vitrine composite (5 panneaux)',
        'Composite storefront (5 panels)',
      ),
    };
  }

  String _measurementSummary() {
    if (_isSlidingStraight && _overallDrawingRect != null) {
      return '${_overallWidthMm.toStringAsFixed(0)} × '
          '${_overallHeightMm.toStringAsFixed(0)}';
    }
    if (_panels.length == 1) {
      final panel = _panels.first;
      return '${panel.widthMm.toStringAsFixed(0)} × '
          '${panel.heightMm.toStringAsFixed(0)}';
    }
    if (_panels.length > 1) {
      final totalW = _overallWidthMm;
      final totalH = _overallHeightMm;
      if (totalW > 0 && totalH > 0) {
        return '${totalW.toStringAsFixed(0)} × ${totalH.toStringAsFixed(0)}';
      }
      return '${_panels.length} ${_tr('قطع', 'panneaux', 'panels')}';
    }
    final w =
        _overallWidthMmValue ??
        (_overallWidthMm > 0 ? _overallWidthMm : 1000.0);
    final h =
        _overallHeightMmValue ??
        (_overallHeightMm > 0 ? _overallHeightMm : 2000.0);
    return '${w.toStringAsFixed(0)} × ${h.toStringAsFixed(0)}';
  }

  void _startPanel(DragStartDetails details) {
    final position = _canvasPosition(details.localPosition);
    if (_sablageEnabled) {
      _drawStart = position;
      setState(
        () => _draftSablageOffsetMm = _sablageOffsetFromPosition(position.dy),
      );
      return;
    }
    _draggingHole = _findMovableHole(position);
    if (_draggingHole != null && _kitLocked) {
      _draggingHole = null;
      _refuseWhenKitLocked();
      return;
    }
    if (_draggingHole != null) {
      _pushHistory();
      _drawStart = details.localPosition;
      return;
    }
    final panelIndex = _panels.lastIndexWhere(
      (panel) => panel.rect.contains(position),
    );
    if (panelIndex >= 0) {
      _pushHistory();
      setState(() {
        _selectedPanelIndex = panelIndex;
        _draggingPanelIndex = panelIndex;
      });
      _drawStart = position;
      return;
    }
    _drawStart = position;
    setState(() => _draftPanel = Rect.fromPoints(_drawStart!, _drawStart!));
  }

  void _resizePanel(DragUpdateDetails details) {
    final position = _canvasPosition(details.localPosition);
    if (_sablageEnabled) {
      setState(
        () => _draftSablageOffsetMm = _sablageOffsetFromPosition(
          math.min(_drawStart?.dy ?? position.dy, position.dy),
        ),
      );
      return;
    }
    if (_draggingHole != null) {
      _moveHoleGroup(details.delta / _zoom);
      return;
    }
    if (_draggingPanelIndex != null) {
      _movePanel(details.delta / _zoom);
      return;
    }
    final start = _drawStart;
    if (start == null) return;
    setState(() => _draftPanel = Rect.fromPoints(start, details.localPosition));
  }

  void _finishPanel(DragEndDetails details) {
    if (_sablageEnabled) {
      final offset = _draftSablageOffsetMm;
      _drawStart = null;
      setState(() => _draftSablageOffsetMm = null);
      if (offset != null) _addSablageBand(offset);
      return;
    }
    if (_draggingHole != null) {
      _draggingHole = null;
      _drawStart = null;
      return;
    }
    if (_draggingPanelIndex != null) {
      _draggingPanelIndex = null;
      _drawStart = null;
      return;
    }
    final panel = _draftPanel;
    _drawStart = null;
    if (panel == null || panel.width < 12 || panel.height < 12) {
      setState(() => _draftPanel = null);
      return;
    }
    if (_panelOverlapsExisting(panel)) {
      setState(() => _draftPanel = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'لا يمكن رسم إطار داخل إطار أو فوق إطار موجود.',
              'Un cadre ne peut pas être dessiné à l’intérieur ou sur un autre cadre.',
              'A frame cannot be drawn inside or over another frame.',
            ),
          ),
        ),
      );
      return;
    }
    final pixelsPerMillimeter = _freehandPixelsPerMillimeter();
    final widthMm = _freehandMillimetersFromPixels(
      panel.width,
      pixelsPerMillimeter,
      _freehandMaxWidthMm,
    );
    final heightMm = _freehandMillimetersFromPixels(
      panel.height,
      pixelsPerMillimeter,
      _freehandMaxHeightMm,
    );
    _pushHistory();
    setState(() {
      if (_isSlidingStraight) {
        _overallDrawingRect = panel;
        _overallWidthMmValue = widthMm;
        _overallHeightMmValue = heightMm;
        _setDefaultSlidingDoorWidth(widthMm);
        _applySlidingLayout();
      } else {
        _panels.add(
          _GlassPanel(rect: panel, widthMm: widthMm, heightMm: heightMm),
        );
        _overallWidthMmValue = _panels
            .map((p) => p.widthMm)
            .fold<double>(0.0, (a, b) => a + b);
        _overallHeightMmValue = _panels.map((p) => p.heightMm).reduce(math.max);
      }
      _selectedPanelIndex = _panels.isEmpty ? null : _panels.length - 1;
      _draftPanel = null;
    });
  }

  void _movePanel(Offset delta) {
    final index = _draggingPanelIndex;
    if (index == null || index < 0 || index >= _panels.length) return;
    setState(() {
      if (_isSlidingStraight && _overallDrawingRect != null) {
        _overallDrawingRect = _overallDrawingRect!.shift(delta);
        _applySlidingLayout();
        return;
      }
      _panels[index].rect = _panels[index].rect.shift(delta);
    });
  }

  bool _panelOverlapsExisting(Rect panel) {
    if (_isSlidingStraight && _overallDrawingRect != null) return true;
    return _panels.any(
      (existing) =>
          existing.rect.overlaps(panel) ||
          existing.rect.contains(panel.center) ||
          panel.contains(existing.rect.center),
    );
  }

  _MovableHoleTarget? _findMovableHole(Offset position) {
    for (var panelIndex = 0; panelIndex < _panels.length; panelIndex++) {
      final panel = _panels[panelIndex];
      final scaleX = panel.widthMm <= 0
          ? 1.0
          : panel.rect.width / panel.widthMm;
      final scaleY = panel.heightMm <= 0
          ? 1.0
          : panel.rect.height / panel.heightMm;

      // Direct handle bar hit test (between top and bottom handle holes)
      final handleHoles = panel.holes
          .where((h) => h.purpose.startsWith('handle_'))
          .toList();
      if (handleHoles.length >= 2) {
        final h1 = handleHoles[0];
        final h2 = handleHoles[1];
        final topH = h1.yMm <= h2.yMm ? h1 : h2;
        final botH = identical(topH, h1) ? h2 : h1;
        final handleX = panel.rect.left + topH.xMm * scaleX;
        final topY = panel.rect.top + topH.yMm * scaleY;
        final botY = panel.rect.top + botH.yMm * scaleY;
        final handleBarRect = Rect.fromLTRB(
          handleX - 22,
          topY - 24,
          handleX + 22,
          botY + 24,
        );
        if (handleBarRect.contains(position)) {
          final topHoleIdx = panel.holes.indexOf(topH);
          return _MovableHoleTarget(
            panelIndex: panelIndex,
            holeIndex: topHoleIdx,
            purpose: topH.purpose,
          );
        }
      }

      // Direct towel bar hit test (between left and right towel holes)
      final towelHoles = panel.holes
          .where((h) => h.purpose.startsWith('towel_'))
          .toList();
      if (towelHoles.length >= 2) {
        final h1 = towelHoles[0];
        final h2 = towelHoles[1];
        final leftH = h1.xMm <= h2.xMm ? h1 : h2;
        final rightH = identical(leftH, h1) ? h2 : h1;
        final leftX = panel.rect.left + leftH.xMm * scaleX;
        final rightX = panel.rect.left + rightH.xMm * scaleX;
        final towelY = panel.rect.top + leftH.yMm * scaleY;
        final towelBarRect = Rect.fromLTRB(
          leftX - 24,
          towelY - 22,
          rightX + 24,
          towelY + 22,
        );
        if (towelBarRect.contains(position)) {
          final leftHoleIdx = panel.holes.indexOf(leftH);
          return _MovableHoleTarget(
            panelIndex: panelIndex,
            holeIndex: leftHoleIdx,
            purpose: leftH.purpose,
          );
        }
      }

      for (var holeIndex = 0; holeIndex < panel.holes.length; holeIndex++) {
        final hole = panel.holes[holeIndex];
        if (!hole.isMovable) continue;
        final holePosition = Offset(
          panel.rect.left + hole.xMm * scaleX,
          panel.rect.top + hole.yMm * scaleY,
        );
        final holeLabelHitBox = Rect.fromCenter(
          center: holePosition + const Offset(0, 14),
          width: 110,
          height: 32,
        );
        final holeRadius = math.max(
          6.0,
          hole.diameterMm * math.min(scaleX, scaleY) / 2,
        );
        final fromLeft = hole.xMm <= panel.widthMm / 2;
        final horizontalHoleEdge =
            holePosition.dx + (fromLeft ? -holeRadius : holeRadius);
        final horizontalGlassEdge = fromLeft
            ? panel.rect.left
            : panel.rect.right;
        final horizontalDimensionHitBox = Rect.fromCenter(
          center: Offset(
            (horizontalGlassEdge + horizontalHoleEdge) / 2,
            holePosition.dy - 11,
          ),
          width: 110,
          height: 30,
        );
        final fromTop = hole.yMm <= panel.heightMm / 2;
        final verticalHoleEdge =
            holePosition.dy + (fromTop ? -holeRadius : holeRadius);
        final verticalGlassEdge = fromTop ? panel.rect.top : panel.rect.bottom;
        final verticalDimensionHitBox = Rect.fromCenter(
          center: Offset(
            holePosition.dx + 13,
            (verticalGlassEdge + verticalHoleEdge) / 2,
          ),
          width: 42,
          height: 110,
        );
        if ((holePosition - position).distance <= 28 ||
            holeLabelHitBox.contains(position) ||
            horizontalDimensionHitBox.contains(position) ||
            verticalDimensionHitBox.contains(position)) {
          return _MovableHoleTarget(
            panelIndex: panelIndex,
            holeIndex: holeIndex,
            purpose: hole.purpose,
          );
        }
      }
    }
    return null;
  }

  void _moveHoleGroup(Offset delta) {
    final target = _draggingHole;
    if (target == null || target.panelIndex >= _panels.length) return;
    final panel = _panels[target.panelIndex];
    final scaleX = panel.widthMm <= 0 ? 1.0 : panel.rect.width / panel.widthMm;
    final scaleY = panel.heightMm <= 0
        ? 1.0
        : panel.rect.height / panel.heightMm;
    final dxMm = delta.dx / scaleX;
    final dyMm = delta.dy / scaleY;
    if (target.holeIndex >= panel.holes.length) return;
    final hole = panel.holes[target.holeIndex];

    // Handle pair: both top and bottom holes move together strictly preserving entraxe and vertical alignment
    if (hole.purpose.startsWith('handle_')) {
      final hTop = panel.holes
          .where((h) => h.purpose == 'handle_top')
          .firstOrNull;
      final hBottom = panel.holes
          .where((h) => h.purpose == 'handle_bottom')
          .firstOrNull;
      if (hTop != null && hBottom != null) {
        final spacing = (hBottom.yMm - hTop.yMm).abs();
        final entraxe = spacing > 0
            ? spacing
            : (_handleSpacingMm > 0 ? _handleSpacingMm : 200.0);
        final diam = math.max(hTop.diameterMm, hBottom.diameterMm);

        final minimumHandleCenter = 44.0 + diam / 2;
        final newX = (hTop.xMm + dxMm)
            .clamp(
              minimumHandleCenter,
              math.max(
                minimumHandleCenter,
                panel.widthMm - minimumHandleCenter,
              ),
            )
            .toDouble();

        final minY = diam / 2;
        final maxY = math.max(minY, panel.heightMm - diam / 2 - entraxe);
        final newTopY = (hTop.yMm + dyMm).clamp(minY, maxY).toDouble();
        final newBottomY = newTopY + entraxe;

        setState(() {
          hTop.xMm = newX;
          hTop.yMm = newTopY;
          hBottom.xMm = newX;
          hBottom.yMm = newBottomY;

          _holeOverrides['handle_top'] = _HoleOverride(
            xMm: newX,
            yMm: newTopY,
            diameterMm: hTop.diameterMm,
          );
          _holeOverrides['handle_bottom'] = _HoleOverride(
            xMm: newX,
            yMm: newBottomY,
            diameterMm: hBottom.diameterMm,
          );

          _handleEdgeOffsetMm = (panel.widthMm - newX <= newX)
              ? (panel.widthMm - newX)
              : newX;
          _handleCenterFromTopMm = (newTopY + newBottomY) / 2;
        });
        return;
      }
    }

    // Towel bar pair: both left and right holes move together strictly preserving horizontal spacing
    if (hole.purpose.startsWith('towel_')) {
      final hLeft = panel.holes
          .where((h) => h.purpose == 'towel_left')
          .firstOrNull;
      final hRight = panel.holes
          .where((h) => h.purpose == 'towel_right')
          .firstOrNull;
      if (hLeft != null && hRight != null) {
        final spacing = (hRight.xMm - hLeft.xMm).abs();
        final entraxe = spacing > 0
            ? spacing
            : (_towelSpacingMm > 0 ? _towelSpacingMm : 450.0);
        final diam = math.max(hLeft.diameterMm, hRight.diameterMm);

        final minX = diam / 2;
        final maxX = math.max(minX, panel.widthMm - diam / 2 - entraxe);
        final newLeftX = (hLeft.xMm + dxMm).clamp(minX, maxX).toDouble();
        final newRightX = newLeftX + entraxe;

        final newY = (hLeft.yMm + dyMm)
            .clamp(diam / 2, panel.heightMm - diam / 2)
            .toDouble();

        setState(() {
          hLeft.xMm = newLeftX;
          hLeft.yMm = newY;
          hRight.xMm = newRightX;
          hRight.yMm = newY;

          _holeOverrides['towel_left'] = _HoleOverride(
            xMm: newLeftX,
            yMm: newY,
            diameterMm: hLeft.diameterMm,
          );
          _holeOverrides['towel_right'] = _HoleOverride(
            xMm: newRightX,
            yMm: newY,
            diameterMm: hRight.diameterMm,
          );

          _towelCenterFromLeftMm = (newLeftX + newRightX) / 2;
          _towelCenterFromTopMm = newY;
        });
        return;
      }
    }

    final diameter = hole.diameterMm.clamp(
      1.0,
      math.min(panel.widthMm, panel.heightMm),
    );

    setState(() {
      hole.xMm = (hole.xMm + dxMm)
          .clamp(diameter / 2, panel.widthMm - diameter / 2)
          .toDouble();
      hole.yMm = (hole.yMm + dyMm)
          .clamp(diameter / 2, panel.heightMm - diameter / 2)
          .toDouble();
      _holeOverrides[hole.purpose] = _HoleOverride(
        xMm: hole.xMm,
        yMm: hole.yMm,
        diameterMm: hole.diameterMm,
      );
    });
  }

  Future<double?> _promptDimensionDialog({
    required String title,
    required double initialValue,
    required String label,
    double min = 1,
    double max = 6000,
  }) async {
    final controller = TextEditingController(
      text: initialValue.toStringAsFixed(0),
    );
    String? error;
    final res = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogInnerContext, setDialogState) {
          void submit() {
            final val = _parseMillimeters(controller.text);
            if (val == null || val < min || val > max) {
              setDialogState(() {
                error = _tr(
                  'يرجى إدخال قيمة صحيحة بين ${min.toStringAsFixed(0)} و ${max.toStringAsFixed(0)} مم',
                  'Valeur invalide',
                  'Invalid value',
                );
              });
              return;
            }
            Navigator.pop(dialogContext, val);
          }

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: label,
                    suffixText: 'mm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogInnerContext).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(_tr('موافق', 'OK', 'OK')),
              ),
            ],
          );
        },
      ),
    );
    // showDialog completes as soon as Navigator.pop is called, while the
    // dialog widgets remain mounted during the reverse route animation.
    // Waiting 250ms prevents page rebuilds from touching deactivating InheritedElements
    // (which triggers Failed assertion: '_dependents.isEmpty').
    // Do not synchronously dispose controller here because the closing route might still paint it.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return res;
  }

  bool _tryHandleSpacingTap(Offset position) {
    for (final panel in _panels) {
      final groupedHoles = <String, List<_GlassHole>>{};
      for (final hole in panel.holes) {
        final group = hole.purpose.startsWith('handle_')
            ? 'handle'
            : hole.purpose.startsWith('towel_')
            ? 'towel'
            : hole.purpose.startsWith('door_top_')
            ? 'door_top'
            : hole.purpose;
        groupedHoles.putIfAbsent(group, () => []).add(hole);
      }
      final scaleX = panel.widthMm <= 0
          ? 1.0
          : panel.rect.width / panel.widthMm;
      final scaleY = panel.heightMm <= 0
          ? 1.0
          : panel.rect.height / panel.heightMm;
      for (final entry in groupedHoles.entries) {
        if (entry.value.length != 2) continue;
        final h1 = entry.value[0];
        final h2 = entry.value[1];
        final p1 = Offset(
          panel.rect.left + h1.xMm * scaleX,
          panel.rect.top + h1.yMm * scaleY,
        );
        final p2 = Offset(
          panel.rect.left + h2.xMm * scaleX,
          panel.rect.top + h2.yMm * scaleY,
        );
        final isHorizontal = (p2.dx - p1.dx).abs() >= (p2.dy - p1.dy).abs();
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final labelOffset = isHorizontal
            ? const Offset(0, -11)
            : const Offset(13, 0);
        final labelCenter = mid + labelOffset;
        final hitBox = Rect.fromCenter(
          center: labelCenter,
          width: 70,
          height: 35,
        );
        if (hitBox.contains(position) || (position - mid).distance <= 24) {
          final group = entry.key;
          final currentSpacing = group == 'handle'
              ? _handleSpacingMm
              : group == 'towel'
              ? _towelSpacingMm
              : isHorizontal
              ? (h2.xMm - h1.xMm).abs()
              : (h2.yMm - h1.yMm).abs();
          if (_refuseWhenKitLocked()) return true;
          _promptDimensionDialog(
            title: group == 'handle'
                ? _tr(
                    'تباعد ثقوب مقبض الباب',
                    'Espacement poignée',
                    'Handle spacing',
                  )
                : group == 'towel'
                ? _tr(
                    'تباعد ثقوب مقبض المناشف',
                    'Espacement porte-serviette',
                    'Towel spacing',
                  )
                : _tr(
                    'التباعد بين الثقبين',
                    'Espacement trous',
                    'Hole spacing',
                  ),
            initialValue: currentSpacing,
            label: _tr('التباعد', 'Espacement', 'Spacing'),
            min: 20,
            max: 1500,
          ).then((newSpacing) {
            if (newSpacing != null && mounted) {
              _pushHistory();
              setState(() {
                if (group == 'handle') {
                  _handleSpacingMm = newSpacing;
                  _holeOverrides.remove('handle_top');
                  _holeOverrides.remove('handle_bottom');
                  _updatePanelsForHandles();
                } else if (group == 'towel') {
                  _towelSpacingMm = newSpacing;
                  _updatePanelsForHandles();
                } else {
                  if (isHorizontal) {
                    final centerXMm = (h1.xMm + h2.xMm) / 2;
                    h1.xMm = centerXMm - newSpacing / 2;
                    h2.xMm = centerXMm + newSpacing / 2;
                  } else {
                    final centerYMm = (h1.yMm + h2.yMm) / 2;
                    h1.yMm = centerYMm - newSpacing / 2;
                    h2.yMm = centerYMm + newSpacing / 2;
                  }
                }
              });
            }
          });
          return true;
        }
      }
    }
    return false;
  }

  bool _tryHoleHorizontalDimensionTap(Offset position) {
    for (final panel in _panels) {
      final scaleX = panel.widthMm <= 0
          ? 1.0
          : panel.rect.width / panel.widthMm;
      final scaleY = panel.heightMm <= 0
          ? 1.0
          : panel.rect.height / panel.heightMm;
      for (final hole in panel.holes) {
        final center = Offset(
          panel.rect.left + hole.xMm * scaleX,
          panel.rect.top + hole.yMm * scaleY,
        );
        final radius = math.max(
          3.0,
          hole.diameterMm * math.min(scaleX, scaleY) / 2,
        );
        final leftMm = (hole.xMm - hole.diameterMm / 2).clamp(
          0.0,
          panel.widthMm,
        );
        final rightMm = (panel.widthMm - hole.xMm - hole.diameterMm / 2).clamp(
          0.0,
          panel.widthMm,
        );
        final fromLeft = leftMm <= rightMm;
        final holeEdgeX = fromLeft ? center.dx - radius : center.dx + radius;
        final glassEdgeX = fromLeft ? panel.rect.left : panel.rect.right;
        final hitBox = Rect.fromCenter(
          center: Offset((glassEdgeX + holeEdgeX) / 2, center.dy - 11),
          width: (glassEdgeX - holeEdgeX).abs().clamp(30.0, 100.0),
          height: 32,
        );
        if (hitBox.contains(position)) {
          final currentVal = fromLeft ? leftMm : rightMm;
          if (_refuseWhenKitLocked()) return true;
          _promptDimensionDialog(
            title: fromLeft
                ? _tr(
                    'المسافة عن الحافة اليسرى',
                    'Distance bord gauche',
                    'Distance from left edge',
                  )
                : _tr(
                    'المسافة عن الحافة اليمنى',
                    'Distance bord droit',
                    'Distance from right edge',
                  ),
            initialValue: currentVal,
            label: _tr('المسافة', 'Distance', 'Distance'),
            min: 5,
            max: panel.widthMm - hole.diameterMm,
          ).then((newVal) {
            if (newVal != null && mounted) {
              _pushHistory();
              setState(() {
                if (hole.purpose.startsWith('handle_')) {
                  _handleEdgeOffsetMm = newVal + hole.diameterMm / 2;
                  _holeOverrides.remove('handle_top');
                  _holeOverrides.remove('handle_bottom');
                  _updatePanelsForHandles();
                } else if (hole.purpose.startsWith('door_top_')) {
                  _doorTopHoleSideOffsetMm = newVal;
                  if (_isSlidingStraight) _applySlidingLayout();
                } else {
                  hole.xMm = fromLeft
                      ? newVal + hole.diameterMm / 2
                      : panel.widthMm - newVal - hole.diameterMm / 2;
                  _holeOverrides[hole.purpose] = _HoleOverride(
                    xMm: hole.xMm,
                    yMm: hole.yMm,
                    diameterMm: hole.diameterMm,
                  );
                }
              });
            }
          });
          return true;
        }
      }
    }
    return false;
  }

  bool _tryHoleVerticalDimensionTap(Offset position) {
    for (final panel in _panels) {
      final scaleX = panel.widthMm <= 0
          ? 1.0
          : panel.rect.width / panel.widthMm;
      final scaleY = panel.heightMm <= 0
          ? 1.0
          : panel.rect.height / panel.heightMm;
      for (final hole in panel.holes) {
        final center = Offset(
          panel.rect.left + hole.xMm * scaleX,
          panel.rect.top + hole.yMm * scaleY,
        );
        final radius = math.max(
          3.0,
          hole.diameterMm * math.min(scaleX, scaleY) / 2,
        );
        final topMm = (hole.yMm - hole.diameterMm / 2).clamp(
          0.0,
          panel.heightMm,
        );
        final bottomMm = (panel.heightMm - hole.yMm - hole.diameterMm / 2)
            .clamp(0.0, panel.heightMm);
        final fromTop = topMm <= bottomMm;
        final holeEdgeY = fromTop ? center.dy - radius : center.dy + radius;
        final glassEdgeY = fromTop ? panel.rect.top : panel.rect.bottom;
        final hitBox = Rect.fromCenter(
          center: Offset(center.dx + 13, (glassEdgeY + holeEdgeY) / 2),
          width: 38,
          height: (glassEdgeY - holeEdgeY).abs().clamp(30.0, 100.0),
        );
        if (hitBox.contains(position)) {
          final currentVal = fromTop ? topMm : bottomMm;
          if (_refuseWhenKitLocked()) return true;
          _promptDimensionDialog(
            title: fromTop
                ? _tr(
                    'المسافة عن الحافة العلوية',
                    'Distance bord haut',
                    'Distance from top edge',
                  )
                : _tr(
                    'المسافة عن الحافة السفلية',
                    'Distance bord bas',
                    'Distance from bottom edge',
                  ),
            initialValue: currentVal,
            label: _tr('المسافة', 'Distance', 'Distance'),
            min: 5,
            max: panel.heightMm - hole.diameterMm,
          ).then((newVal) {
            if (newVal != null && mounted) {
              _pushHistory();
              setState(() {
                if (hole.purpose.startsWith('handle_')) {
                  _handleCenterFromTopMm = fromTop
                      ? newVal + _handleSpacingMm / 2 + hole.diameterMm / 2
                      : panel.heightMm -
                            newVal -
                            _handleSpacingMm / 2 -
                            hole.diameterMm / 2;
                  _holeOverrides.remove('handle_top');
                  _holeOverrides.remove('handle_bottom');
                  _updatePanelsForHandles();
                } else if (hole.purpose.startsWith('door_top_')) {
                  _doorTopHoleTopOffsetMm = newVal;
                  if (_isSlidingStraight) _applySlidingLayout();
                } else {
                  hole.yMm = fromTop
                      ? newVal + hole.diameterMm / 2
                      : panel.heightMm - newVal - hole.diameterMm / 2;
                  _holeOverrides[hole.purpose] = _HoleOverride(
                    xMm: hole.xMm,
                    yMm: hole.yMm,
                    diameterMm: hole.diameterMm,
                  );
                }
              });
            }
          });
          return true;
        }
      }
    }
    return false;
  }

  bool _tryHoleOrLabelTap(Offset position) {
    for (var pIdx = 0; pIdx < _panels.length; pIdx++) {
      final panel = _panels[pIdx];
      final scaleX = panel.widthMm <= 0
          ? 1.0
          : panel.rect.width / panel.widthMm;
      final scaleY = panel.heightMm <= 0
          ? 1.0
          : panel.rect.height / panel.heightMm;
      for (var hIdx = 0; hIdx < panel.holes.length; hIdx++) {
        final hole = panel.holes[hIdx];
        final center = Offset(
          panel.rect.left + hole.xMm * scaleX,
          panel.rect.top + hole.yMm * scaleY,
        );
        final radius = math.max(
          6.0,
          hole.diameterMm * math.min(scaleX, scaleY) / 2,
        );
        final labelHitBox = Rect.fromCenter(
          center: center + const Offset(0, 14),
          width: 80,
          height: 28,
        );
        if (labelHitBox.contains(position)) {
          if (_refuseWhenKitLocked()) return true;
          _promptDimensionDialog(
            title: _tr('قطر الثقب', 'Diamètre du trou', 'Hole diameter'),
            initialValue: hole.diameterMm,
            label: _tr('القطر', 'Diamètre', 'Diameter'),
            min: 6,
            max: 100,
          ).then((newDia) {
            if (newDia != null && mounted) {
              _pushHistory();
              setState(() {
                hole.diameterMm = newDia;
                _holeDiameterMm = newDia;
                _holeOverrides[hole.purpose] = _HoleOverride(
                  xMm: hole.xMm,
                  yMm: hole.yMm,
                  diameterMm: newDia,
                );
              });
            }
          });
          return true;
        }
        if ((center - position).distance <= radius + 12) {
          _editMovableHole(
            _MovableHoleTarget(
              panelIndex: pIdx,
              holeIndex: hIdx,
              purpose: hole.purpose,
            ),
          );
          return true;
        }
      }
    }
    return false;
  }

  bool _tryPanelDimensionTap(Offset position) {
    if (_panels.isEmpty) return false;
    final minLeft = _panels.map((p) => p.rect.left).reduce(math.min);
    final maxRight = _panels.map((p) => p.rect.right).reduce(math.max);
    final minTop = _panels.map((p) => p.rect.top).reduce(math.min);
    final maxBottom = _panels.map((p) => p.rect.bottom).reduce(math.max);

    // Outer top width hit box:
    final totalWidthHitBox = Rect.fromLTRB(
      minLeft - 20,
      minTop - 60,
      maxRight + 20,
      minTop,
    );
    if (totalWidthHitBox.contains(position)) {
      _editMeasurements(focusHeight: false);
      return true;
    }

    // Outer left/right height hit boxes:
    final leftHeightHitBox = Rect.fromLTRB(
      minLeft - 70,
      minTop - 10,
      minLeft,
      maxBottom + 10,
    );
    final rightHeightHitBox = Rect.fromLTRB(
      maxRight,
      minTop - 10,
      maxRight + 70,
      maxBottom + 10,
    );
    if (leftHeightHitBox.contains(position) ||
        rightHeightHitBox.contains(position)) {
      _editMeasurements(focusHeight: true);
      return true;
    }

    // Individual panel width:
    for (var i = 0; i < _panels.length; i++) {
      final panel = _panels[i];
      final panelTopWidthBox = Rect.fromLTRB(
        panel.rect.left - 4,
        panel.rect.top - 30,
        panel.rect.right + 4,
        panel.rect.top,
      );
      if (panelTopWidthBox.contains(position)) {
        if (_workType == GlassWorkType.vitrineComposite && _panels.length >= 4) {
          _editVitrinePanelWidthWithCompensation(i);
        } else {
          _editMeasurements(focusHeight: false);
        }
        return true;
      }
    }
    return false;
  }

  /// Interactive compensation dialog for Vitrine Composite panels
  Future<void> _editVitrinePanelWidthWithCompensation(int panelIndex) async {
    if (panelIndex >= _panels.length) return;
    final targetPanel = _panels[panelIndex];
    final oldWidth = targetPanel.widthMm;
    final widthController = TextEditingController(text: oldWidth.toStringAsFixed(0));
    String targetOption = 'doors_equal'; // 'doors_equal', 'door_1', 'door_2', 'opposite_fixe'
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.tune_rounded, color: Colors.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tr(
                      'تعديل عرض اللوح وتعويض الفارق',
                      'Modifier la largeur et compenser',
                      'Edit panel width & compensate',
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _tr(
                          'اللوح المحدد: ${targetPanel.role} (العرض الحالي: ${oldWidth.toStringAsFixed(0)} مم)',
                          'Panneau sélectionné : ${targetPanel.role} (${oldWidth.toStringAsFixed(0)} mm)',
                          'Selected panel: ${targetPanel.role} (${oldWidth.toStringAsFixed(0)} mm)',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: widthController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: false),
                      decoration: InputDecoration(
                        labelText: _tr('العرض الجديد', 'Nouvelle largeur', 'New width'),
                        suffixText: 'mm',
                        border: const OutlineInputBorder(),
                        helperText: targetPanel.isDoor
                            ? _tr('تنبيه: عرض الباب لا يتجاوز 900 مم', 'Max 900 mm pour la porte', 'Door max 900 mm')
                            : null,
                      ),
                      onChanged: (_) => setDialogState(() => error = null),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _tr(
                        'أين يضاف / ينقص مقدار هذا التغيير؟',
                        'Où appliquer la compensation du delta ?',
                        'Where should the dimension delta be compensated?',
                      ),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      value: 'doors_equal',
                      groupValue: targetOption,
                      title: Text(_tr('من البابين بالتساوي', 'Des 2 portes équitablement', 'Both doors equally')),
                      onChanged: (val) => setDialogState(() => targetOption = val!),
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'door_1',
                      groupValue: targetOption,
                      title: Text(_tr('من الباب الأول فقط', 'De la première porte seulement', 'Door 1 only')),
                      onChanged: (val) => setDialogState(() => targetOption = val!),
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'door_2',
                      groupValue: targetOption,
                      title: Text(_tr('من الباب الثاني فقط', 'De la 2ème porte seulement', 'Door 2 only')),
                      onChanged: (val) => setDialogState(() => targetOption = val!),
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'opposite_fixe',
                      groupValue: targetOption,
                      title: Text(_tr('من الثابت المقابل', 'Du panneau fixe opposé', 'Opposite fixed panel')),
                      onChanged: (val) => setDialogState(() => targetOption = val!),
                      dense: true,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final newW = _parseMillimeters(widthController.text);
                  if (newW == null || newW <= 50) {
                    setDialogState(() => error = _tr('يرجى إدخال عرض صحيح', 'Largeur invalide', 'Invalid width'));
                    return;
                  }
                  if (targetPanel.isDoor && newW > 900) {
                    setDialogState(() => error = _tr('عرض الباب لا يمكن أن يتجاوز 900 مم', 'Max porte 900 mm', 'Door width max 900 mm'));
                    return;
                  }
                  Navigator.pop(dialogCtx, true);
                },
                child: Text(_tr('تطبيق التعويض', 'Appliquer', 'Apply')),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      final newW = _parseMillimeters(widthController.text)!;
      final delta = newW - oldWidth;
      if (delta == 0) return;

      _pushHistory();
      setState(() {
        targetPanel.widthMm = newW;

        final doors = _panels.where((p) => p.isDoor).toList();
        final fixes = _panels.where((p) => !p.isDoor && !p.role.contains('imposte')).toList();

        if (targetOption == 'doors_equal' && doors.isNotEmpty) {
          final deltaPerDoor = delta / doors.length;
          for (final d in doors) {
            d.widthMm = (d.widthMm - deltaPerDoor).clamp(100.0, 900.0);
          }
        } else if (targetOption == 'door_1' && doors.isNotEmpty) {
          doors.first.widthMm = (doors.first.widthMm - delta).clamp(100.0, 900.0);
        } else if (targetOption == 'door_2' && doors.length > 1) {
          doors[1].widthMm = (doors[1].widthMm - delta).clamp(100.0, 900.0);
        } else if (targetOption == 'opposite_fixe' && fixes.isNotEmpty) {
          final oppFixe = fixes.lastWhere((p) => p != targetPanel, orElse: () => fixes.first);
          oppFixe.widthMm = (oppFixe.widthMm - delta).clamp(100.0, 4000.0);
        }

        // Re-align canvas display rects horizontally
        final bottomPanels = _panels.where((p) => !p.role.contains('imposte')).toList();
        if (bottomPanels.isNotEmpty) {
          final totalBottomW = bottomPanels.fold<double>(0.0, (s, p) => s + p.widthMm);
          final minLeft = bottomPanels.map((p) => p.rect.left).reduce(math.min);
          final maxRight = bottomPanels.map((p) => p.rect.right).reduce(math.max);
          final displayTotalW = maxRight - minLeft;
          final scale = displayTotalW / totalBottomW;

          double curX = minLeft;
          const gap = 3.0;
          for (final p in bottomPanels) {
            final dispW = p.widthMm * scale;
            p.rect = Rect.fromLTWH(curX, p.rect.top, dispW, p.rect.height);
            curX += dispW + gap;
          }

          // Top imposte spans the whole width if present
          final imposte = _panels.where((p) => p.role.contains('imposte')).firstOrNull;
          if (imposte != null) {
            imposte.widthMm = totalBottomW;
            imposte.rect = Rect.fromLTWH(minLeft, imposte.rect.top, curX - minLeft - gap, imposte.rect.height);
          }

          _overallWidthMmValue = totalBottomW;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'تم تعويض أبعاد الفاترينة بنجاح',
              'Dimensions compensées avec succès',
              'Vitrine dimensions compensated successfully',
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleCanvasTap(TapUpDetails details) {
    final position = _canvasPosition(details.localPosition);
    if (_tryHandleSpacingTap(position)) return;
    if (_tryHoleHorizontalDimensionTap(position)) return;
    if (_tryHoleVerticalDimensionTap(position)) return;
    if (_tryHoleOrLabelTap(position)) return;
    if (_tryPanelDimensionTap(position)) return;

    final panelIndex = _panels.lastIndexWhere(
      (panel) => panel.rect.contains(position),
    );
    setState(() => _selectedPanelIndex = panelIndex < 0 ? null : panelIndex);
  }

  void _handleSablageDoubleTap() {
    // Decorative frosting is edited as measured bands.  A double tap on the
    // drawing is the fast entry point to the same precise editor used by the
    // toolbar, so the user can draw first and enter exact dimensions after.
    if (!_sablageEnabled) return;
    _editSablageOptions();
  }

  bool get _sablageEnabled =>
      _sablageMode == _SablageMode.decorative && _sablageDrawingActive;

  double _number(TextEditingController controller, double fallback) =>
      _parseMillimeters(controller.text) ?? fallback;

  // A phone pixel is not a millimeter. Use the drawing area as a scaled
  // work surface so a full-screen gesture can represent large glass pieces.
  double _freehandPixelsPerMillimeter() {
    if (_canvasSize == Size.zero) return 1.0;
    final usableWidth = math.max(1.0, _canvasSize.width - 16.0);
    final usableHeight = math.max(1.0, _canvasSize.height - 16.0);
    return math
        .min(
          usableWidth / _freehandMaxWidthMm,
          usableHeight / _freehandMaxHeightMm,
        )
        .clamp(0.05, 1.0)
        .toDouble();
  }

  double _freehandMillimetersFromPixels(
    double pixels,
    double pixelsPerMillimeter,
    double maximum,
  ) {
    return (pixels / pixelsPerMillimeter).clamp(1.0, maximum).toDouble();
  }

  double _freehandWidthMmFromPixels(double pixels) =>
      _freehandMillimetersFromPixels(
        pixels,
        _freehandPixelsPerMillimeter(),
        _freehandMaxWidthMm,
      );

  double _freehandHeightMmFromPixels(double pixels) =>
      _freehandMillimetersFromPixels(
        pixels,
        _freehandPixelsPerMillimeter(),
        _freehandMaxHeightMm,
      );

  double _workshopCompensation() => _defaultDoorHeightIncreaseMm;

  // For a sliding cabin, the fixed panel receives the 30 mm workshop
  // allowance in width. The door keeps the exact width entered by the user.
  double _fixedWidthCompensation() => _defaultFixedWidthIncreaseMm;

  double _defaultSlidingDoorWidth(double overallWidthMm) {
    return overallWidthMm <= 1700.0 ? overallWidthMm / 2 : 800.0;
  }

  void _setDefaultSlidingDoorWidth(double overallWidthMm) {
    if (_doorWidthCustomized || overallWidthMm <= 0) return;
    _doorWidthController.text = _defaultSlidingDoorWidth(
      overallWidthMm,
    ).toStringAsFixed(0);
  }

  double _doorWidth() => _number(_doorWidthController, 800.0);

  double _sablageBandWidth() => _number(
    _sablageBandWidthController,
    40.0,
  ).clamp(1.0, double.infinity).toDouble();

  void _applySlidingLayout() {
    final overall = _overallDrawingRect;
    if (overall == null) return;
    final drawnWidthMm = _overallWidthMm;
    final drawnHeightMm = _overallHeightMm;
    // The door keeps the entered width. The remaining width belongs to the
    // fixed panel, plus the workshop's 30 mm width allowance.
    final practicalWidth = drawnWidthMm;
    final doorWidth = _doorWidth();
    final fixedWidth = practicalWidth - doorWidth + _fixedWidthCompensation();
    if (fixedWidth <= 0) {
      _panels
        ..clear()
        ..add(
          _GlassPanel(
            rect: overall,
            widthMm: practicalWidth,
            heightMm: drawnHeightMm,
            role: 'overall',
          ),
        );
      return;
    }

    final physicalPanelsWidth = math.max(1.0, doorWidth + fixedWidth);
    // The real panels include the 30 mm workshop overlap in their dimensions.
    // Only a tiny visual gap is shown so the drawing stays clean.
    const gap = _slidingVisualGapPx;
    final doorHeightMm = drawnHeightMm + _workshopCompensation();
    final doorDisplayHeight = drawnHeightMm <= 0
        ? overall.height
        : overall.height * doorHeightMm / drawnHeightMm;
    var layoutRect = overall;
    // The door is taller than the fixed panel from the top side. Keep their
    // lower edges aligned so the workshop compensation appears above them.
    final doorTop = layoutRect.bottom - doorDisplayHeight;
    if (_canvasSize != Size.zero && doorTop < 44) {
      layoutRect = layoutRect.shift(Offset(0, 44 - doorTop));
      _overallDrawingRect = layoutRect;
    }
    final available = math.max(1.0, layoutRect.width - gap).toDouble();
    final doorDisplayWidth = available * doorWidth / physicalPanelsWidth;
    final fixedDisplayWidth = available * fixedWidth / physicalPanelsWidth;
    final doorRect = Rect.fromLTWH(
      _doorOnLeft ? layoutRect.left : layoutRect.right - doorDisplayWidth,
      layoutRect.bottom - doorDisplayHeight,
      doorDisplayWidth,
      doorDisplayHeight,
    );
    final fixedRect = Rect.fromLTWH(
      _doorOnLeft ? doorRect.right + gap : layoutRect.left,
      layoutRect.top,
      fixedDisplayWidth,
      layoutRect.height,
    );
    // Holes the user drilled (free holes, catalogue accessories) are not
    // part of the layout rules: keep them when the layout is rebuilt.
    List<_GlassHole> userHoles(String role, double widthMm, double heightMm) => [
      for (final panel in _panels.where((p) => p.role == role))
        for (final hole in panel.holes)
          if ((hole.purpose.startsWith('custom_') ||
                  hole.purpose.startsWith('acc_')) &&
              hole.xMm + hole.diameterMm / 2 <= widthMm &&
              hole.yMm + hole.diameterMm / 2 <= heightMm)
            hole,
    ];
    final doorUserHoles = userHoles('door', doorWidth, doorHeightMm);
    final fixedUserHoles = userHoles('fixed', fixedWidth, drawnHeightMm);
    _panels
      ..clear()
      ..addAll([
        _GlassPanel(
          rect: doorRect,
          widthMm: doorWidth,
          heightMm: doorHeightMm,
          role: 'door',
          holes: [
            ..._doorHoles(
              doorWidth,
              doorHeightMm,
              referenceHeightMm: drawnHeightMm,
            ),
            ...doorUserHoles,
          ],
        ),
        _GlassPanel(
          rect: fixedRect,
          widthMm: fixedWidth,
          heightMm: drawnHeightMm,
          role: 'fixed',
          holes: [..._fixedHoles(fixedWidth, drawnHeightMm), ...fixedUserHoles],
        ),
      ]);
    _selectedPanelIndex = 0;
  }

  List<Map<String, dynamic>> _kitHolesForPanel(String panelRole) {
    final legacyTarget =
        _selectedKit?['target_panel']?.toString().toLowerCase() ?? 'door';
    return _activeKitHoles.where((hole) {
      final target =
          (hole['target_panel']?.toString().trim().isNotEmpty == true
                  ? hole['target_panel'].toString()
                  : legacyTarget)
              .toLowerCase();
      return target == 'all' || target == panelRole;
    }).toList();
  }

  List<_GlassHole> _doorHoles(
    double widthMm,
    double heightMm, {
    double? referenceHeightMm,
  }) {
    // A taller sliding door is extended upward. Use the fixed panel's top as
    // the measurement origin so the door holes stay level with the fixed
    // panel. The extra 30 mm is deliberately excluded from this reference.
    final alignedHeightMm = (referenceHeightMm ?? heightMm)
        .clamp(0.0, heightMm)
        .toDouble();
    final topAllowanceMm = math.max(0.0, heightMm - alignedHeightMm);
    final middleY = (_handleCenterFromTopMm ?? alignedHeightMm / 2)
        .clamp(
          _handleSpacingMm / 2,
          math.max(
            _handleSpacingMm / 2,
            alignedHeightMm - _handleSpacingMm / 2,
          ),
        )
        .toDouble();
    double safeX(double value) => value
        .clamp(
          _holeDiameterMm / 2,
          math.max(_holeDiameterMm / 2, widthMm - _holeDiameterMm / 2),
        )
        .toDouble();
    double safeY(double value) => value
        .clamp(
          _holeDiameterMm / 2,
          math.max(_holeDiameterMm / 2, heightMm - _holeDiameterMm / 2),
        )
        .toDouble();
    final holes = <_GlassHole>[];
    final doorKitHoles = _kitHolesForPanel('door');
    if (_activeKitHoles.isNotEmpty) {
      for (final h in doorKitHoles) {
        final minW = (h['min_panel_width_mm'] as num? ?? 0.0).toDouble();
        if (minW > 0 && widthMm < minW) continue;
        final maxW = (h['max_panel_width_mm'] as num? ?? 0.0).toDouble();
        if (maxW > 0 && widthMm > maxW) continue;

        final diamMm = (h['diameter_mm'] as num? ?? _holeDiameterMm).toDouble();
        final offXMm = (h['offset_x_mm'] as num? ?? 80.0).toDouble();
        final offYMm = (h['offset_y_mm'] as num? ?? 35.0).toDouble();
        final refX = h['ref_x'] as String? ?? 'left';
        final refY = h['ref_y'] as String? ?? 'top';
        final mode = h['reference_mode'] as String? ?? 'edge';
        final purpose =
            h['purpose'] as String? ?? 'kit_hole_${h['hole_index']}';

        double x;
        if (refX == 'left') {
          x = mode == 'edge' ? offXMm + diamMm / 2 : offXMm;
        } else if (refX == 'right') {
          x = mode == 'edge' ? widthMm - offXMm - diamMm / 2 : widthMm - offXMm;
        } else {
          x = widthMm / 2;
        }

        double y;
        if (refY == 'top') {
          y = topAllowanceMm + (mode == 'edge' ? offYMm + diamMm / 2 : offYMm);
        } else if (refY == 'bottom') {
          y = heightMm - (mode == 'edge' ? offYMm + diamMm / 2 : offYMm);
        } else {
          y = topAllowanceMm + heightMm / 2;
        }

        holes.add(
          _GlassHole(
            xMm: safeX(x),
            yMm: safeY(y),
            diameterMm: diamMm,
            purpose: purpose,
          ),
        );
      }
    } else {
      holes.addAll([
        _GlassHole(
          xMm: safeX(_doorTopHoleSideOffsetMm),
          yMm: safeY(topAllowanceMm + _doorTopHoleTopOffsetMm),
          diameterMm: _holeDiameterMm,
          purpose: 'door_top_left',
        ),
        _GlassHole(
          xMm: safeX(widthMm - _doorTopHoleSideOffsetMm),
          yMm: safeY(topAllowanceMm + _doorTopHoleTopOffsetMm),
          diameterMm: _holeDiameterMm,
          purpose: 'door_top_right',
        ),
      ]);
    }
    final handleX = (_isSlidingStraight && !_doorOnLeft)
        ? safeX(widthMm - _handleEdgeOffsetMm)
        : safeX(_handleEdgeOffsetMm);
    if (_showDoorHandle) {
      holes.addAll([
        _GlassHole(
          xMm: handleX,
          yMm: safeY(topAllowanceMm + middleY - _handleSpacingMm / 2),
          diameterMm: _holeDiameterMm,
          purpose: 'handle_top',
        ),
        _GlassHole(
          xMm: handleX,
          yMm: safeY(topAllowanceMm + middleY + _handleSpacingMm / 2),
          diameterMm: _holeDiameterMm,
          purpose: 'handle_bottom',
        ),
      ]);
    }
    return holes
        .map(
          (hole) =>
              _applyHoleOverride(hole, widthMm: widthMm, heightMm: heightMm),
        )
        .toList();
  }

  List<_GlassHole> _fixedHoles(double widthMm, double heightMm) {
    final holes = <_GlassHole>[];
    final middleX = (_towelCenterFromLeftMm ?? widthMm / 2)
        .clamp(0.0, widthMm)
        .toDouble();
    final middleY = (_towelCenterFromTopMm ?? heightMm / 2)
        .clamp(
          _towelSpacingMm / 2,
          math.max(_towelSpacingMm / 2, heightMm - _towelSpacingMm / 2),
        )
        .toDouble();
    double safeX(double value) => value
        .clamp(
          _holeDiameterMm / 2,
          math.max(_holeDiameterMm / 2, widthMm - _holeDiameterMm / 2),
        )
        .toDouble();
    double safeY(double value) => value
        .clamp(
          _holeDiameterMm / 2,
          math.max(_holeDiameterMm / 2, heightMm - _holeDiameterMm / 2),
        )
        .toDouble();
    for (final h in _kitHolesForPanel('fixed')) {
      final minWidth = (h['min_panel_width_mm'] as num? ?? 0.0).toDouble();
      if (minWidth > 0 && widthMm < minWidth) continue;
      final maxWidth = (h['max_panel_width_mm'] as num? ?? 0.0).toDouble();
      if (maxWidth > 0 && widthMm > maxWidth) continue;
      final diameter = (h['diameter_mm'] as num? ?? _holeDiameterMm).toDouble();
      final offsetX = (h['offset_x_mm'] as num? ?? 0.0).toDouble();
      final offsetY = (h['offset_y_mm'] as num? ?? 0.0).toDouble();
      final referenceX = h['ref_x']?.toString() ?? 'left';
      final referenceY = h['ref_y']?.toString() ?? 'top';
      final referenceMode = h['reference_mode']?.toString() ?? 'edge';
      final x = referenceX == 'right'
          ? widthMm - offsetX - (referenceMode == 'edge' ? diameter / 2 : 0)
          : referenceX == 'center'
          ? widthMm / 2
          : offsetX + (referenceMode == 'edge' ? diameter / 2 : 0);
      final y = referenceY == 'bottom'
          ? heightMm - offsetY - (referenceMode == 'edge' ? diameter / 2 : 0)
          : referenceY == 'center'
          ? heightMm / 2
          : offsetY + (referenceMode == 'edge' ? diameter / 2 : 0);
      holes.add(
        _GlassHole(
          xMm: safeX(x),
          yMm: safeY(y),
          diameterMm: diameter,
          purpose: h['purpose']?.toString() ?? 'kit_hole_${h['hole_index']}',
        ),
      );
    }

    if (_showTowelHandle) {
      holes.addAll([
        _GlassHole(
          xMm: safeX(middleX - _towelSpacingMm / 2),
          yMm: safeY(middleY),
          diameterMm: _holeDiameterMm,
          purpose: 'towel_left',
        ),
        _GlassHole(
          xMm: safeX(middleX + _towelSpacingMm / 2),
          yMm: safeY(middleY),
          diameterMm: _holeDiameterMm,
          purpose: 'towel_right',
        ),
      ]);
    }
    return holes
        .map(
          (hole) =>
              _applyHoleOverride(hole, widthMm: widthMm, heightMm: heightMm),
        )
        .toList();
  }

  String _handlesButtonLabel() {
    if (_showDoorHandle && _showTowelHandle) {
      return _tr('المقابض (2)', 'Poignées (2)', 'Handles (2)');
    } else if (_showDoorHandle) {
      return _tr('مقبض 200 مم', 'Poignée 200 mm', '200 mm handle');
    } else if (_showTowelHandle) {
      return _tr('مقبض مناشف', 'Porte-serviette', 'Towel handle');
    } else {
      return _tr('بدون مقبض', 'Sans poignée', 'No handles');
    }
  }

  Future<void> _showHandlesSelectionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.pan_tool_outlined, color: Colors.cyan),
              const SizedBox(width: 8),
              Text(
                _tr(
                  'تحديد المقابض',
                  'Sélection des poignées',
                  'Select handles',
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  value: _showDoorHandle,
                  title: Text(
                    _tr(
                      'مقبض الباب (200 مم)',
                      'Poignée de porte (200 mm)',
                      'Door handle (200 mm)',
                    ),
                  ),
                  subtitle: Text(
                    _tr(
                      'التباعد: ${_handleSpacingMm.toStringAsFixed(0)} مم | الحافة: ${_handleEdgeOffsetMm.toStringAsFixed(0)} مم',
                      'Espacement: ${_handleSpacingMm.toStringAsFixed(0)} mm',
                      'Spacing: ${_handleSpacingMm.toStringAsFixed(0)} mm',
                    ),
                  ),
                  onChanged: (val) {
                    _pushHistory();
                    setState(() {
                      _showDoorHandle = val ?? false;
                      _updatePanelsForHandles();
                    });
                    setDialogState(() {});
                  },
                ),
                CheckboxListTile(
                  value: _showTowelHandle,
                  title: Text(
                    _tr(
                      'مقبض المناشف (450 مم)',
                      'Porte-serviette (450 mm)',
                      'Towel handle (450 mm)',
                    ),
                  ),
                  subtitle: Text(
                    _tr(
                      'التباعد: ${_towelSpacingMm.toStringAsFixed(0)} مم',
                      'Espacement: ${_towelSpacingMm.toStringAsFixed(0)} mm',
                      'Spacing: ${_towelSpacingMm.toStringAsFixed(0)} mm',
                    ),
                  ),
                  onChanged: (val) {
                    _pushHistory();
                    setState(() {
                      _showTowelHandle = val ?? false;
                      _updatePanelsForHandles();
                    });
                    setDialogState(() {});
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(
                    _tr(
                      'تعديل موضع وقياسات المقبض',
                      'Modifier la position et les mesures',
                      'Edit handle position & measurements',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _editHandleFromToolbar();
                  },
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('تم', 'Terminé', 'Done')),
            ),
          ],
        ),
      ),
    );
  }

  void _updatePanelsForHandles() {
    if (_isSlidingStraight) {
      if (_overallDrawingRect != null) {
        _applySlidingLayout();
      }
    } else {
      for (final panel in _panels) {
        panel.holes.removeWhere((h) => h.purpose.startsWith('handle_'));
        panel.holes.removeWhere((h) => h.purpose.startsWith('towel_'));
        if (_showDoorHandle && panel.isDoor) {
          panel.holes.addAll(
            _doorHoles(
              panel.widthMm,
              panel.heightMm,
            ).where((h) => h.purpose.startsWith('handle_')),
          );
        }
        if (_showTowelHandle && !panel.isDoor) {
          panel.holes.addAll(_fixedHoles(panel.widthMm, panel.heightMm));
        }
      }
    }
  }

  _GlassHole _applyHoleOverride(
    _GlassHole hole, {
    required double widthMm,
    required double heightMm,
  }) {
    final override = _holeOverrides[hole.purpose];
    if (override == null) return hole;
    final diameter = override.diameterMm
        .clamp(1.0, math.min(widthMm, heightMm))
        .toDouble();
    hole.diameterMm = diameter;
    final minimumX = hole.purpose.startsWith('handle_')
        ? 44.0 + diameter / 2
        : diameter / 2;
    hole.xMm = override.xMm
        .clamp(minimumX, math.max(minimumX, widthMm - minimumX))
        .toDouble();
    hole.yMm = override.yMm
        .clamp(diameter / 2, math.max(diameter / 2, heightMm - diameter / 2))
        .toDouble();
    return hole;
  }

  Future<void> _editMovableHole(_MovableHoleTarget target) async {
    if (_refuseWhenKitLocked()) return;
    if (target.panelIndex >= _panels.length) return;
    final panel = _panels[target.panelIndex];
    if (target.holeIndex >= panel.holes.length) return;
    final hole = panel.holes[target.holeIndex];
    final xController = TextEditingController(
      text: hole.xMm.toStringAsFixed(0),
    );
    final yController = TextEditingController(
      text: hole.yMm.toStringAsFixed(0),
    );
    final diameterController = TextEditingController(
      text: hole.diameterMm.toStringAsFixed(0),
    );
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final dialogWidth = (MediaQuery.sizeOf(context).width - 80.0)
              .clamp(240.0, 420.0)
              .toDouble();
          void submit() {
            final x = _parseMillimeters(xController.text);
            final y = _parseMillimeters(yController.text);
            final diameter = _parseMillimeters(diameterController.text);
            final maxDiameter = math.min(panel.widthMm, panel.heightMm);
            final valid =
                x != null &&
                y != null &&
                diameter != null &&
                diameter > 0 &&
                diameter <= maxDiameter &&
                x >= diameter / 2 &&
                x <= panel.widthMm - diameter / 2 &&
                y >= diameter / 2 &&
                y <= panel.heightMm - diameter / 2;
            if (!valid) {
              setDialogState(
                () => error = _tr(
                  'يجب أن يبقى الثقب كاملًا داخل الزجاج.',
                  'Le trou doit rester entièrement dans le verre.',
                  'The hole must remain completely inside the glass.',
                ),
              );
              return;
            }
            Navigator.pop(dialogContext, true);
          }

          TextField field(
            TextEditingController controller,
            String label, {
            TextInputAction textInputAction = TextInputAction.next,
            bool autofocus = false,
          }) {
            return TextField(
              controller: controller,
              autofocus: autofocus,
              textInputAction: textInputAction,
              onSubmitted: (_) => submit(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: label,
                suffixText: 'mm',
                border: const OutlineInputBorder(),
              ),
            );
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.adjust_rounded,
                  color: Colors.deepOrange.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(_tr('تعديل الثقب', 'Modifier le trou', 'Edit hole')),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field(
                      xController,
                      _tr(
                        'المسافة عن اليسار',
                        'Distance depuis la gauche',
                        'Distance from left',
                      ),
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    field(
                      yController,
                      _tr(
                        'المسافة عن الأعلى',
                        'Distance depuis le haut',
                        'Distance from top',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    field(
                      diameterController,
                      _tr('قطر الثقب', 'Diamètre du trou', 'Hole diameter'),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                xController.text = (panel.widthMm / 2).toStringAsFixed(0);
                              });
                            },
                            icon: const Icon(Icons.align_horizontal_center, size: 16),
                            label: Text(
                              _tr('توسيط X', 'Centrer X', 'Center X'),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                yController.text = (panel.heightMm / 2).toStringAsFixed(0);
                              });
                            },
                            icon: const Icon(Icons.align_vertical_center, size: 16),
                            label: Text(
                              _tr('توسيط Y', 'Centrer Y', 'Center Y'),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: _tr('توسيط كامل في المنتصف', 'Centrer au milieu', 'Center completely'),
                          onPressed: () {
                            setDialogState(() {
                              xController.text = (panel.widthMm / 2).toStringAsFixed(0);
                              yController.text = (panel.heightMm / 2).toStringAsFixed(0);
                            });
                          },
                          icon: const Icon(Icons.filter_center_focus, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _tr(
                        'أقطار قياسية سريعة:',
                        'Diamètres rapides :',
                        'Quick diameters:',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: const [2.0, 4.0, 10.0, 20.0, 30.0, 45.0].map((
                        d,
                      ) {
                        final valStr = d.toStringAsFixed(0);
                        final isSel = diameterController.text == valStr;
                        return ChoiceChip(
                          label: Text('$valStr mm'),
                          selected: isSel,
                          selectedColor: Colors.deepOrange.shade100,
                          onSelected: (_) {
                            setDialogState(() {
                              diameterController.text = valStr;
                            });
                          },
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext, false);
                        final curDia =
                            _parseMillimeters(diameterController.text) ??
                            hole.diameterMm;
                        hole.diameterMm = curDia;
                        _apply4CornerHoles(
                          panel: panel,
                          sourceHole: hole,
                          diameterMm: curDia,
                        );
                      },
                      icon: const Icon(
                        Icons.grid_view_rounded,
                        size: 18,
                        color: Colors.teal,
                      ),
                      label: Text(
                        _tr(
                          'تكرار متناظر في الزوايا الـ 4',
                          'Appliquer aux 4 coins',
                          'Apply to 4 corners',
                        ),
                        style: const TextStyle(
                          color: Colors.teal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.teal),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                  _pushHistory();
                  setState(() {
                    panel.holes.removeAt(target.holeIndex);
                    _holeOverrides.remove(hole.purpose);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _tr('تم حذف الثقب', 'Trou supprimé', 'Hole deleted'),
                      ),
                      // An action keeps a SnackBar open until it is dismissed.
                      persist: false,
                      action: SnackBarAction(
                        label: _tr('تراجع', 'Annuler', 'Undo'),
                        onPressed: _undo,
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 18,
                ),
                label: Text(
                  _tr('حذف', 'Supprimer', 'Delete'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(_tr('موافق', 'OK', 'OK')),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true && mounted) {
      final x = _parseMillimeters(xController.text)!;
      final y = _parseMillimeters(yController.text)!;
      final diameter = _parseMillimeters(diameterController.text)!;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _pushHistory();
      setState(() {
        final panel = _panels[target.panelIndex];
        final updatedHole = panel.holes[target.holeIndex];
        final oldX = updatedHole.xMm;
        final oldY = updatedHole.yMm;
        final dy = y - oldY;
        final dx = x - oldX;

        updatedHole.xMm = x;
        updatedHole.yMm = y;
        updatedHole.diameterMm = diameter;
        _holeOverrides[updatedHole.purpose] = _HoleOverride(
          xMm: x,
          yMm: y,
          diameterMm: diameter,
        );

        if (updatedHole.purpose == 'handle_top') {
          final hBottom = panel.holes
              .where((h) => h.purpose == 'handle_bottom')
              .firstOrNull;
          if (hBottom != null) {
            hBottom.xMm = x;
            hBottom.yMm = (hBottom.yMm + dy)
                .clamp(diameter / 2, panel.heightMm - diameter / 2)
                .toDouble();
            _holeOverrides['handle_bottom'] = _HoleOverride(
              xMm: x,
              yMm: hBottom.yMm,
              diameterMm: hBottom.diameterMm,
            );
          }
        } else if (updatedHole.purpose == 'handle_bottom') {
          final hTop = panel.holes
              .where((h) => h.purpose == 'handle_top')
              .firstOrNull;
          if (hTop != null) {
            hTop.xMm = x;
            hTop.yMm = (hTop.yMm + dy)
                .clamp(diameter / 2, panel.heightMm - diameter / 2)
                .toDouble();
            _holeOverrides['handle_top'] = _HoleOverride(
              xMm: x,
              yMm: hTop.yMm,
              diameterMm: hTop.diameterMm,
            );
          }
        } else if (updatedHole.purpose == 'towel_left') {
          final hRight = panel.holes
              .where((h) => h.purpose == 'towel_right')
              .firstOrNull;
          if (hRight != null) {
            hRight.xMm = (hRight.xMm + dx)
                .clamp(diameter / 2, panel.widthMm - diameter / 2)
                .toDouble();
            hRight.yMm = y;
            _holeOverrides['towel_right'] = _HoleOverride(
              xMm: hRight.xMm,
              yMm: y,
              diameterMm: hRight.diameterMm,
            );
          }
        } else if (updatedHole.purpose == 'towel_right') {
          final hLeft = panel.holes
              .where((h) => h.purpose == 'towel_left')
              .firstOrNull;
          if (hLeft != null) {
            hLeft.xMm = (hLeft.xMm + dx)
                .clamp(diameter / 2, panel.widthMm - diameter / 2)
                .toDouble();
            hLeft.yMm = y;
            _holeOverrides['towel_left'] = _HoleOverride(
              xMm: hLeft.xMm,
              yMm: y,
              diameterMm: hLeft.diameterMm,
            );
          }
        }
      });
    }
  }

  Future<void> _editHandleFromToolbar() async {
    if (_panels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'يرجى إنشاء أو رسم ألواح الزجاج أولاً.',
              'Veuillez d’abord créer les panneaux de verre.',
              'Please create or draw glass panels first.',
            ),
          ),
        ),
      );
      return;
    }

    final door = _panels.where((p) => p.isDoor).firstOrNull;
    if (door == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'لا يوجد باب في النظام الحالي لإضافة مقبض له.',
              'Aucune porte trouvée dans le système actuel.',
              'No door found in the current system.',
            ),
          ),
        ),
      );
      return;
    }

    final handleHole = door.holes.where((h) => h.purpose.startsWith('handle_')).firstOrNull;
    if (handleHole != null) {
      final pIdx = _panels.indexOf(door);
      final hIdx = door.holes.indexOf(handleHole);
      await _editMovableHole(
        _MovableHoleTarget(
          panelIndex: pIdx,
          holeIndex: hIdx,
          purpose: handleHole.purpose,
        ),
      );
    } else {
      // Prompt parametric handle creation dialog
      final spacingCtrl = TextEditingController(text: _handleSpacingMm.toStringAsFixed(0));
      final edgeCtrl = TextEditingController(text: _handleEdgeOffsetMm.toStringAsFixed(0));
      final diaCtrl = TextEditingController(text: _holeDiameterMm.toStringAsFixed(0));
      int holeCount = 2; // 1, 2, 3
      bool isCenterY = true;

      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (dCtx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.pan_tool_outlined, color: Colors.cyan),
                const SizedBox(width: 8),
                Text(
                  _tr(
                    'تخصيص ثقوب المقبض البارامتري',
                    'Personnalisation poignée',
                    'Parametric handle customization',
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(_tr('عدد الثقوب:', 'Nombre de trous :', 'Holes count:')),
                        const Spacer(),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1')),
                            ButtonSegment(value: 2, label: Text('2')),
                            ButtonSegment(value: 3, label: Text('3')),
                          ],
                          selected: {holeCount},
                          onSelectionChanged: (set) => setDialogState(() => holeCount = set.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: diaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _tr('قطر الثقب', 'Diamètre', 'Diameter'),
                        suffixText: 'mm',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (holeCount > 1) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: spacingCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _tr('المسافة بين الثقوب (Entraxe)', 'Entraxe', 'Spacing'),
                          suffixText: 'mm',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: edgeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _tr('المسافة عن الحافة X', 'Distance bord X', 'Edge distance X'),
                        suffixText: 'mm',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: isCenterY,
                      title: Text(_tr('توسيط تلقائي على المحور Y', 'Centrage auto Y', 'Center on Y axis')),
                      onChanged: (val) => setDialogState(() => isCenterY = val),
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: Text(_tr('تطبيق', 'Appliquer', 'Apply')),
              ),
            ],
          ),
        ),
      );

      if (saved == true && mounted) {
        _pushHistory();
        setState(() {
          final dia = _parseMillimeters(diaCtrl.text) ?? 12.0;
          final spacing = _parseMillimeters(spacingCtrl.text) ?? 200.0;
          final edge = _parseMillimeters(edgeCtrl.text) ?? 60.0;

          _handleSpacingMm = spacing;
          _handleEdgeOffsetMm = edge;
          _showDoorHandle = true;

          door.holes.removeWhere((h) => h.purpose.startsWith('handle_'));
          final centerY = door.heightMm / 2;

          if (holeCount == 1) {
            door.holes.add(
              _GlassHole(
                xMm: edge,
                yMm: isCenterY ? centerY : centerY,
                diameterMm: dia,
                purpose: 'handle_center',
              ),
            );
          } else if (holeCount == 2) {
            door.holes.addAll([
              _GlassHole(
                xMm: edge,
                yMm: centerY - spacing / 2,
                diameterMm: dia,
                purpose: 'handle_top',
              ),
              _GlassHole(
                xMm: edge,
                yMm: centerY + spacing / 2,
                diameterMm: dia,
                purpose: 'handle_bottom',
              ),
            ]);
          } else if (holeCount == 3) {
            door.holes.addAll([
              _GlassHole(
                xMm: edge,
                yMm: centerY - spacing,
                diameterMm: dia,
                purpose: 'handle_top',
              ),
              _GlassHole(
                xMm: edge,
                yMm: centerY,
                diameterMm: dia,
                purpose: 'handle_mid',
              ),
              _GlassHole(
                xMm: edge,
                yMm: centerY + spacing,
                diameterMm: dia,
                purpose: 'handle_bottom',
              ),
            ]);
          }
        });
      }
    }
  }

  _MovableHoleTarget? _findHoleByPurpose(String purpose) {
    for (var panelIndex = 0; panelIndex < _panels.length; panelIndex++) {
      final holeIndex = _panels[panelIndex].holes.indexWhere(
        (hole) => hole.purpose == purpose,
      );
      if (holeIndex >= 0) {
        return _MovableHoleTarget(
          panelIndex: panelIndex,
          holeIndex: holeIndex,
          purpose: purpose,
        );
      }
    }
    return null;
  }

  void _apply4CornerHoles({
    _GlassPanel? panel,
    _GlassHole? sourceHole,
    double? diameterMm,
  }) {
    if (_panels.isEmpty) return;
    if (_refuseWhenKitLocked()) return;
    final targetPanel =
        panel ??
        (_selectedPanelIndex != null && _selectedPanelIndex! < _panels.length
            ? _panels[_selectedPanelIndex!]
            : _panels.first);
    final diam = (diameterMm ?? sourceHole?.diameterMm ?? _holeDiameterMm)
        .clamp(1.0, math.min(targetPanel.widthMm, targetPanel.heightMm))
        .toDouble();

    double dxMm;
    double dyMm;
    if (sourceHole != null) {
      dxMm = math.min(sourceHole.xMm, targetPanel.widthMm - sourceHole.xMm);
      dyMm = math.min(sourceHole.yMm, targetPanel.heightMm - sourceHole.yMm);
    } else {
      dxMm = 60.0;
      dyMm = 60.0;
    }
    dxMm = dxMm.clamp(diam / 2, targetPanel.widthMm / 2).toDouble();
    dyMm = dyMm.clamp(diam / 2, targetPanel.heightMm / 2).toDouble();

    _pushHistory();
    setState(() {
      targetPanel.holes.removeWhere(
        (h) =>
            h.purpose.startsWith('corner_4_') ||
            (sourceHole != null && h.purpose == sourceHole.purpose),
      );

      final corners = [
        {'x': dxMm, 'y': dyMm, 'tag': 'tl'},
        {'x': targetPanel.widthMm - dxMm, 'y': dyMm, 'tag': 'tr'},
        {'x': dxMm, 'y': targetPanel.heightMm - dyMm, 'tag': 'bl'},
        {
          'x': targetPanel.widthMm - dxMm,
          'y': targetPanel.heightMm - dyMm,
          'tag': 'br',
        },
      ];

      for (final c in corners) {
        final newHole = _GlassHole(
          xMm: (c['x'] as num).toDouble(),
          yMm: (c['y'] as num).toDouble(),
          diameterMm: diam,
          purpose:
              'corner_4_${c['tag']}_${DateTime.now().microsecondsSinceEpoch}',
        );
        targetPanel.holes.add(newHole);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'تم تطبيق 4 ثقوب متناظرة على الزوايا: ${dxMm.toStringAsFixed(0)} × ${dyMm.toStringAsFixed(0)} مم (Ø ${diam.toStringAsFixed(0)} مم)',
            '4 trous appliqués aux coins avec succès',
            '4 corner holes applied successfully',
          ),
        ),
        // An action keeps a SnackBar open until it is dismissed.
        persist: false,
        action: SnackBarAction(
          label: _tr('تراجع', 'Annuler', 'Undo'),
          onPressed: _undo,
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleCanvasLongPress(LongPressStartDetails details) {
    if (_refuseWhenKitLocked()) return;
    final position = _canvasPosition(details.localPosition);
    final target = _findMovableHole(position);
    if (target != null && target.panelIndex < _panels.length) {
      final panel = _panels[target.panelIndex];
      if (target.holeIndex < panel.holes.length) {
        final hole = panel.holes[target.holeIndex];
        _pushHistory();
        setState(() {
          panel.holes.removeAt(target.holeIndex);
          _holeOverrides.remove(hole.purpose);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'تم حذف الثقب (Ø ${hole.diameterMm.toStringAsFixed(0)} مم)',
                'Trou supprimé',
                'Hole deleted',
              ),
            ),
            // An action keeps a SnackBar open until it is dismissed.
            persist: false,
            action: SnackBarAction(
              label: _tr('تراجع', 'Annuler', 'Undo'),
              onPressed: _undo,
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    for (final panel in _panels) {
      final scaleY = panel.heightMm <= 0
          ? 1.0
          : panel.rect.height / panel.heightMm;
      for (var i = 0; i < panel.hinges.length; i++) {
        final hinge = panel.hinges[i];
        final hY = panel.rect.top + hinge.yMm * scaleY;
        final hX = hinge.side == 'left' ? panel.rect.left : panel.rect.right;
        if ((Offset(hX, hY) - position).distance <= 36) {
          _pushHistory();
          setState(() => panel.hinges.removeAt(i));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _tr('تم حذف المفصلة', 'Charnière supprimée', 'Hinge deleted'),
              ),
              // An action keeps a SnackBar open until it is dismissed.
              persist: false,
              action: SnackBarAction(
                label: _tr('تراجع', 'Annuler', 'Undo'),
                onPressed: _undo,
              ),
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
      }
    }
  }

  void _handleToolDrop(String tool, Offset canvasPos) {
    if (_panels.isEmpty) return;
    if (tool != 'tool_handle' && _refuseWhenKitLocked()) return;
    final pIdx = _panels.lastIndexWhere((p) => p.rect.contains(canvasPos));
    final panel = _panels[pIdx >= 0 ? pIdx : 0];

    final scaleX = panel.widthMm <= 0 ? 1.0 : panel.rect.width / panel.widthMm;
    final scaleY = panel.heightMm <= 0
        ? 1.0
        : panel.rect.height / panel.heightMm;
    final xMm = ((canvasPos.dx - panel.rect.left) / scaleX)
        .clamp(_holeDiameterMm / 2, panel.widthMm - _holeDiameterMm / 2)
        .toDouble();
    final yMm = ((canvasPos.dy - panel.rect.top) / scaleY)
        .clamp(_holeDiameterMm / 2, panel.heightMm - _holeDiameterMm / 2)
        .toDouble();

    if (tool == 'tool_hole') {
      _pushHistory();
      setState(() {
        final newHole = _GlassHole(
          xMm: xMm,
          yMm: yMm,
          diameterMm: _holeDiameterMm,
          purpose: 'custom_${DateTime.now().microsecondsSinceEpoch}',
        );
        panel.holes.add(newHole);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'تمت إضافة ثقب (Ø ${_holeDiameterMm.toStringAsFixed(0)} مم) إلى الرسم',
              'Trou ajouté',
              'Hole added',
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (tool == 'tool_hinge') {
      _addExtraHinge(
        panel: panel,
        yMm: yMm,
        side: xMm <= panel.widthMm / 2 ? 'left' : 'right',
      );
    } else if (tool == 'tool_handle') {
      _showDatabaseHandlesPicker();
    }
  }

  void _addExtraHinge({_GlassPanel? panel, double? yMm, String? side}) {
    if (_panels.isEmpty) return;
    if (_refuseWhenKitLocked()) return;
    final targetPanel =
        panel ??
        _panels.firstWhere((p) => p.isDoor, orElse: () => _panels.first);
    final targetY = (yMm ?? (targetPanel.heightMm / 2))
        .clamp(50.0, targetPanel.heightMm - 50.0)
        .toDouble();
    final targetSide = side ?? (_doorOnLeft ? 'left' : 'right');
    _pushHistory();
    setState(() {
      targetPanel.hinges.add(_GlassHinge(yMm: targetY, side: targetSide));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'تمت إضافة مفصلة إضافية للباب',
            'Charnière ajoutée',
            'Hinge added',
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadAllHandleOptions() async {
    final list = <Map<String, dynamic>>[];
    try {
      final tgItems = await _db.getTemperedGlassItems(category: 'poignee');
      final kitHandleIds = _activeKitComponents
          .where((row) => row['component_type'] == 'handle')
          .map((row) => (row['item_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      list.addAll(
        kitHandleIds.isEmpty
            ? tgItems
            : tgItems.where(
                (item) => kitHandleIds.contains((item['id'] as num?)?.toInt()),
              ),
      );
    } catch (_) {}

    try {
      final allAcc = await _db.readAccessories();
      final handles = allAcc.where((a) {
        final cat = (a['category'] ?? a['type'] ?? '').toString().toLowerCase();
        final name = (a['name'] ?? '').toString().toLowerCase();
        return cat.contains('poign') ||
            cat.contains('handle') ||
            cat.contains('مقبض') ||
            name.contains('poign') ||
            name.contains('handle') ||
            name.contains('مقبض');
      }).toList();

      for (final h in handles) {
        final hName = h['name']?.toString() ?? '';
        if (!list.any((existing) => existing['name'] == hName)) {
          double entraxe = 200.0;
          int holesCount = 2;
          if (hName.contains('300')) entraxe = 300.0;
          if (hName.contains('450')) entraxe = 450.0;
          if (hName.contains('500')) entraxe = 500.0;
          if (hName.contains('bouton') ||
              hName.contains('دائري') ||
              hName.contains('زر')) {
            entraxe = 0.0;
            holesCount = 1;
          }
          list.add({
            'id': h['id'],
            'name': hName,
            'category': 'poignee',
            'category_name': 'المقابض',
            'price': (h['price'] as num?)?.toDouble() ?? 3200.0,
            'entraxe': entraxe,
            'holes_count': holesCount,
            'notes': h['notes'] ?? '',
          });
        }
      }
    } catch (_) {}

    if (list.isEmpty) {
      list.addAll([
        {
          'id': -1,
          'name': 'مقبض أنبوبي ستانلس 200 مم (Poignée inox 200mm)',
          'category': 'poignee',
          'price': 3800.0,
          'entraxe': 200.0,
          'holes_count': 2,
        },
        {
          'id': -2,
          'name': 'مقبض أنبوبي ستانلس 300 مم (Poignée inox 300mm)',
          'category': 'poignee',
          'price': 4800.0,
          'entraxe': 300.0,
          'holes_count': 2,
        },
        {
          'id': -3,
          'name': 'مقبض مناشف كابين دوش 450 مم (Porte-serviette 450mm)',
          'category': 'poignee',
          'price': 4800.0,
          'entraxe': 450.0,
          'holes_count': 2,
        },
        {
          'id': -4,
          'name': 'مقبض دائري مفرد للباب (Bouton rond inox)',
          'category': 'poignee',
          'price': 2200.0,
          'entraxe': 0.0,
          'holes_count': 1,
        },
      ]);
    }

    return list;
  }

  void _applyHandleFromDatabase(Map<String, dynamic> handleItem) {
    final design = GlassHandleDesignCatalog.resolveForItem(handleItem);
    final rawEntraxe = (handleItem['entraxe'] as num?)?.toDouble();
    final entraxe = (rawEntraxe != null && rawEntraxe > 0)
        ? rawEntraxe
        : (design.defaultEntraxe > 0 ? design.defaultEntraxe : 200.0);
    final holesCount =
        (handleItem['holes_count'] as num?)?.toInt() ??
        design.defaultHolesCount;
    final itemId = (handleItem['id'] as num?)?.toInt();
    final handleShape = design.shape;
    final handleDesignCode = design.code;

    _pushHistory();
    setState(() {
      _showDoorHandle = true;
      _handleSpacingMm = entraxe > 0 ? entraxe : 0.0;
      _selectedHandleShape = handleShape;
      _selectedHandleDesignCode = handleDesignCode;
      if (itemId != null && itemId > 0) {
        _selectedAccessories[itemId] = 1;
      }

      for (final panel in _panels) {
        if (panel.isDoor) {
          panel.holes.removeWhere((h) => h.purpose.startsWith('handle_'));
          final middleY = panel.heightMm / 2;
          final handleX = (_isSlidingStraight && !_doorOnLeft)
              ? (panel.widthMm - _handleEdgeOffsetMm)
              : _handleEdgeOffsetMm;

          if (holesCount <= 1 || entraxe == 0) {
            panel.holes.add(
              _GlassHole(
                xMm: handleX,
                yMm: middleY,
                diameterMm: _holeDiameterMm,
                purpose: 'handle_top',
              ),
            );
          } else {
            panel.holes.addAll([
              _GlassHole(
                xMm: handleX,
                yMm: middleY - entraxe / 2,
                diameterMm: _holeDiameterMm,
                purpose: 'handle_top',
              ),
              _GlassHole(
                xMm: handleX,
                yMm: middleY + entraxe / 2,
                diameterMm: _holeDiameterMm,
                purpose: 'handle_bottom',
              ),
            ]);
          }
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'تم تطبيق المقبض: ${handleItem['name'] ?? ''}',
            'Poignée appliquée avec succès',
            'Handle applied successfully',
          ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showDatabaseHandlesPicker() async {
    final handles = await _loadAllHandleOptions();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (sheetCtx, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.pan_tool_outlined, color: Colors.cyan.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tr(
                        'أنواع المقابض المتوفرة في قاعدة البيانات',
                        'Modèles de poignées dans le catalogue',
                        'Database Handle Models',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: _tr(
                      'تحديد يدوي للمقابض',
                      'Sélection manuelle',
                      'Manual handle selection',
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showHandlesSelectionDialog();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: handles.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final item = handles[idx];
                    final name = item['name']?.toString() ?? '';
                    final price = _colorPrice(item, 0.0);
                    final entraxe =
                        (item['entraxe'] as num?)?.toDouble() ?? 200.0;
                    final isKnob = entraxe == 0;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      leading: GlassHandleThumbnailView(
                        imagePath: item['image_path']?.toString(),
                        designCode:
                            item['handle_design_code']?.toString() ??
                            GlassHandleDesignCatalog.resolveForItem(item).code,
                        size: 48,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        isKnob
                            ? _tr(
                                'مقبض دائري (ثقب مفرد)',
                                'Bouton rond (trou unique)',
                                'Knob (single hole)',
                              )
                            : _tr(
                                'التباعد بين الثقوب: ${entraxe.toStringAsFixed(0)} مم',
                                'Entraxe : ${entraxe.toStringAsFixed(0)} mm',
                                'Hole spacing: ${entraxe.toStringAsFixed(0)} mm',
                              ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (price > 0)
                            Text(
                              '${price.toStringAsFixed(0)} DZD',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade800,
                                fontSize: 13,
                              ),
                            ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _applyHandleFromDatabase(item);
                            },
                            child: Text(
                              _tr('تطبيق في الرسم', 'Appliquer', 'Apply'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPresetSystemsGallery() async {
    final systems = [
      {
        'code': 'coulissante',
        'title_ar': 'كابينة دوش منزلقة (I)',
        'title_fr': 'Cabine coulissante (I)',
        'title_en': 'Sliding cabin (I)',
        'desc_ar': 'لوح ثابت + باب منزلق بسكة علوية ورولات ستانلس',
        'desc_fr': 'Panneau fixe + porte coulissante avec rail inox',
        'workType': GlassWorkType.slidingShowerCabin,
        'doorOnLeft': true,
        'defaultW': 1200.0,
        'defaultH': 2000.0,
      },
      {
        'code': 'cabine_l',
        'title_ar': 'Cabin Douche L (باب على اليسار)',
        'title_fr': 'Cabin Douche L (porte à gauche)',
        'title_en': 'Cabin Douche L (left door)',
        'desc_ar': 'كابينة زاوية L، الباب يسار مع 3 مفاصل تلقائياً ومقبض',
        'desc_fr': 'Cabine en angle, porte à gauche avec 3 charnières',
        'workType': GlassWorkType.showerCabin,
        'doorOnLeft': true,
        'defaultW': 900.0,
        'defaultH': 2000.0,
      },
      {
        'code': 'cabine_r',
        'title_ar': 'Cabin Douche R (باب على اليمين)',
        'title_fr': 'Cabin Douche R (porte à droite)',
        'title_en': 'Cabin Douche R (right door)',
        'desc_ar': 'كابينة زاوية L، الباب يمين مع 3 مفاصل تلقائياً ومقبض',
        'desc_fr': 'Cabine en angle, porte à droite avec 3 charnières',
        'workType': GlassWorkType.showerCabin,
        'doorOnLeft': false,
        'defaultW': 900.0,
        'defaultH': 2000.0,
      },
      {
        'code': 'cabine_porte',
        'title_ar': 'كابينة دوش بباب مفصلي واحد',
        'title_fr': 'Cabine porte simple battante',
        'title_en': 'Single door shower cabin',
        'desc_ar': 'باب زجاجي مفصلي كامل مع 3 مفاصل جدارية ومقبض',
        'desc_fr': 'Porte battante avec 3 charnières murales',
        'workType': GlassWorkType.singleDoorShowerCabin,
        'doorOnLeft': true,
        'defaultW': 800.0,
        'defaultH': 2000.0,
      },
      {
        'code': 'cabine_fixe_porte',
        'title_ar': 'كابينة دوش ثابت + باب مفصلي',
        'title_fr': 'Fixe + porte battante',
        'title_en': 'Fixed panel + door',
        'desc_ar': 'لوح ثابت متصل بباب مفصلي بواسطة 3 مفاصل زجاج/زجاج',
        'desc_fr': 'Panneau fixe relié à une porte battante 3 charnières',
        'workType': GlassWorkType.showerCabin,
        'doorOnLeft': true,
        'defaultW': 1000.0,
        'defaultH': 2000.0,
      },
      {
        'code': 'vitrine_1p',
        'title_ar': 'واجهة فيترين بباب واحد',
        'title_fr': 'Vitrine à 1 porte',
        'title_en': '1-door vitrine storefront',
        'desc_ar': 'واجهة محل بباب محوري فردي مع محور أرضي ومقبض طويل',
        'desc_fr': 'Façade vitrée avec porte sur pivot de sol',
        'workType': GlassWorkType.vitrineSingleDoor,
        'doorOnLeft': true,
        'defaultW': 900.0,
        'defaultH': 2100.0,
      },
      {
        'code': 'vitrine_2p',
        'title_ar': 'واجهة فيترين ببابين مزدوجين',
        'title_fr': 'Vitrine à 2 portes',
        'title_en': '2-door vitrine storefront',
        'desc_ar': 'واجهة ببابين متقابلين مع محاور أرضية وأقفال سفلية',
        'desc_fr': 'Façade vitrée avec double porte pivotante',
        'workType': GlassWorkType.vitrineDoubleDoor,
        'doorOnLeft': true,
        'defaultW': 1800.0,
        'defaultH': 2100.0,
      },
      {
        'code': 'vitrine_composite_5p',
        'title_ar': 'واجهة فيترين مجمعة (ثوابت + بابين + إمبوست)',
        'title_fr': 'Vitrine composite (Fixes + 2 Portes + Imposte)',
        'title_en': 'Composite Vitrine (Fixed + 2 Doors + Transom)',
        'desc_ar': 'واجهة هندسية كاملة: ثابت أيسر + باب أيسر + باب أيمن + ثابت أيمن + إمبوست علوي',
        'desc_fr': 'Façade 5 panneaux : 2 fixes latéraux, 2 portes centrales et imposte supérieure',
        'workType': GlassWorkType.vitrineComposite,
        'doorOnLeft': true,
        'defaultW': 3600.0,
        'defaultH': 2600.0,
      },
      {
        'code': 'paroi_fixe',
        'title_ar': 'حاجز دوش ثابت (Paroi fixe)',
        'title_fr': 'Paroi de douche fixe',
        'title_en': 'Fixed shower screen',
        'desc_ar': 'لوح زجاجي ثابت مع ذراع تثبيت علوي بدون مفاصل',
        'desc_fr': 'Panneau fixe avec barre de stabilisation haute',
        'workType': GlassWorkType.showerCabin,
        'doorOnLeft': true,
        'defaultW': 1000.0,
        'defaultH': 2000.0,
      },
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 720,
          constraints: const BoxConstraints(maxHeight: 650),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_rounded,
                    color: Colors.cyan.shade800,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _tr(
                        'الأنظمة الجاهزة للزجاج المقسّى بصورها التوضيحية',
                        'Systèmes prêts avec aperçus visuels',
                        'Preset Glass Systems with Visual Preview',
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisExtent: 190,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: systems.length,
                  itemBuilder: (context, idx) {
                    final sys = systems[idx];
                    final code = sys['code'] as String;
                    final title = _tr(
                      sys['title_ar'] as String,
                      sys['title_fr'] as String,
                      sys['title_en'] as String,
                    );
                    final desc = _tr(
                      sys['desc_ar'] as String,
                      sys['desc_fr'] as String,
                      sys['desc_en'] as String,
                    );

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(dialogCtx);
                        _applyPresetSystem(sys);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.shade200),
                          color: Colors.white,
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 4),
                            Expanded(
                              child: _SystemThumbnailWidget(
                                systemCode: code,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.cyan.shade900,
                              ),
                            ),
                            Text(
                              desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyPresetSystem(Map<String, dynamic> sys) {
    final workType = sys['workType'] as GlassWorkType;
    final doorOnLeft = sys['doorOnLeft'] as bool;
    final defaultW = (sys['defaultW'] as num).toDouble();
    final defaultH = (sys['defaultH'] as num).toDouble();
    final code = sys['code'] as String;

    _pushHistory();
    setState(() {
      _workType = workType;
      _doorOnLeft = doorOnLeft;
      _overallWidthMmValue = defaultW;
      _overallHeightMmValue = defaultH;

      if (workType == GlassWorkType.slidingShowerCabin) {
        final screenCenter = _canvasSize.center(Offset.zero);
        _overallDrawingRect = Rect.fromCenter(
          center: screenCenter,
          width: 340,
          height: 260,
        );
        _setDefaultSlidingDoorWidth(defaultW);
        _applySlidingLayout();
      } else if (code == 'cabine_l' ||
          code == 'cabine_r' ||
          code == 'cabine_fixe_porte') {
        _overallDrawingRect = null;
        final doorW = code == 'cabine_fixe_porte'
            ? defaultW * 0.45
            : defaultW * 0.52;
        final fixedW = defaultW - doorW;
        final screenCenter = _canvasSize == Size.zero
            ? const Offset(250, 200)
            : _canvasSize.center(Offset.zero);
        final totalDisplayW = 320.0;
        final totalDisplayH = 250.0;
        final doorDisplayW = totalDisplayW * (doorW / defaultW);
        final fixedDisplayW = totalDisplayW - doorDisplayW - 6.0;

        _panels.clear();
        if (doorOnLeft) {
          final doorPanel = _GlassPanel(
            rect: Rect.fromLTWH(
              screenCenter.dx - totalDisplayW / 2,
              screenCenter.dy - totalDisplayH / 2,
              doorDisplayW,
              totalDisplayH,
            ),
            widthMm: doorW,
            heightMm: defaultH,
            role: 'door',
          );
          doorPanel.ensureDoorHinges(hingeSide: 'left');
          doorPanel.holes.addAll([
            _GlassHole(
              xMm: doorW - 50,
              yMm: defaultH / 2 - 100,
              diameterMm: _holeDiameterMm,
              purpose: 'handle_top',
            ),
            _GlassHole(
              xMm: doorW - 50,
              yMm: defaultH / 2 + 100,
              diameterMm: _holeDiameterMm,
              purpose: 'handle_bottom',
            ),
          ]);

          final fixedPanel = _GlassPanel(
            rect: Rect.fromLTWH(
              screenCenter.dx - totalDisplayW / 2 + doorDisplayW + 6.0,
              screenCenter.dy - totalDisplayH / 2,
              fixedDisplayW,
              totalDisplayH,
            ),
            widthMm: fixedW,
            heightMm: defaultH,
            role: 'fixed',
          );

          _panels.addAll([doorPanel, fixedPanel]);
        } else {
          final fixedPanel = _GlassPanel(
            rect: Rect.fromLTWH(
              screenCenter.dx - totalDisplayW / 2,
              screenCenter.dy - totalDisplayH / 2,
              fixedDisplayW,
              totalDisplayH,
            ),
            widthMm: fixedW,
            heightMm: defaultH,
            role: 'fixed',
          );

          final doorPanel = _GlassPanel(
            rect: Rect.fromLTWH(
              screenCenter.dx - totalDisplayW / 2 + fixedDisplayW + 6.0,
              screenCenter.dy - totalDisplayH / 2,
              doorDisplayW,
              totalDisplayH,
            ),
            widthMm: doorW,
            heightMm: defaultH,
            role: 'door',
          );
          doorPanel.ensureDoorHinges(hingeSide: 'right');
          doorPanel.holes.addAll([
            _GlassHole(
              xMm: 50,
              yMm: defaultH / 2 - 100,
              diameterMm: _holeDiameterMm,
              purpose: 'handle_top',
            ),
            _GlassHole(
              xMm: 50,
              yMm: defaultH / 2 + 100,
              diameterMm: _holeDiameterMm,
              purpose: 'handle_bottom',
            ),
          ]);

          _panels.addAll([fixedPanel, doorPanel]);
        }
        _selectedPanelIndex = 0;
      } else if (workType == GlassWorkType.vitrineDoubleDoor) {
        _overallDrawingRect = null;
        final screenCenter = _canvasSize == Size.zero
            ? const Offset(250, 200)
            : _canvasSize.center(Offset.zero);
        const gap = 6.0;
        final halfW = defaultW / 2;
        final displayHalfW = 150.0;
        final displayH = 250.0;

        final leftDoor = _GlassPanel(
          rect: Rect.fromLTWH(
            screenCenter.dx - displayHalfW - gap / 2,
            screenCenter.dy - displayH / 2,
            displayHalfW,
            displayH,
          ),
          widthMm: halfW,
          heightMm: defaultH,
          role: 'vitrine_left',
        );
        leftDoor.ensureDoorHinges(hingeSide: 'left');
        leftDoor.holes.addAll([
          _GlassHole(
            xMm: halfW - 60,
            yMm: defaultH / 2 - 150,
            diameterMm: _holeDiameterMm,
            purpose: 'handle_top',
          ),
          _GlassHole(
            xMm: halfW - 60,
            yMm: defaultH / 2 + 150,
            diameterMm: _holeDiameterMm,
            purpose: 'handle_bottom',
          ),
        ]);

        final rightDoor = _GlassPanel(
          rect: Rect.fromLTWH(
            screenCenter.dx + gap / 2,
            screenCenter.dy - displayH / 2,
            displayHalfW,
            displayH,
          ),
          widthMm: halfW,
          heightMm: defaultH,
          role: 'vitrine_right',
        );
        rightDoor.ensureDoorHinges(hingeSide: 'right');
        rightDoor.holes.addAll([
          _GlassHole(
            xMm: 60,
            yMm: defaultH / 2 - 150,
            diameterMm: _holeDiameterMm,
            purpose: 'handle_top',
          ),
          _GlassHole(
            xMm: 60,
            yMm: defaultH / 2 + 150,
            diameterMm: _holeDiameterMm,
            purpose: 'handle_bottom',
          ),
        ]);

        _panels.clear();
        _panels.addAll([leftDoor, rightDoor]);
        _selectedPanelIndex = 0;
      } else if (workType == GlassWorkType.vitrineComposite) {
        _overallDrawingRect = null;
        final screenCenter = _canvasSize == Size.zero
            ? const Offset(250, 200)
            : _canvasSize.center(Offset.zero);

        // Standard Storefront Vitrine Composite proportions:
        // Door height standard: 2100mm, max width 900mm.
        final doorHeight = math.min(2100.0, defaultH > 500 ? defaultH - 500 : defaultH * 0.8);
        final imposteHeight = math.max(0.0, defaultH - doorHeight);
        final doorWidth = math.min(900.0, defaultW / 4);
        final fixedWidth = math.max(100.0, (defaultW - (doorWidth * 2)) / 2);

        // Canvas display coordinates scaling
        final displayTotalW = 420.0;
        final displayTotalH = 260.0;
        final scaleX = displayTotalW / defaultW;
        final scaleY = displayTotalH / defaultH;

        final displayImposteH = imposteHeight * scaleY;
        final displayBottomH = doorHeight * scaleY;
        final displayFixedW = fixedWidth * scaleX;
        final displayDoorW = doorWidth * scaleX;

        const gap = 3.0;
        final leftOriginX = screenCenter.dx - displayTotalW / 2;
        final topOriginY = screenCenter.dy - displayTotalH / 2;
        final bottomTopY = topOriginY + displayImposteH + (imposteHeight > 0 ? gap : 0.0);

        // 1. Top Imposte (Transom) if height allows
        _GlassPanel? impostePanel;
        if (imposteHeight > 0) {
          impostePanel = _GlassPanel(
            rect: Rect.fromLTWH(
              leftOriginX,
              topOriginY,
              displayTotalW,
              displayImposteH,
            ),
            widthMm: defaultW,
            heightMm: imposteHeight,
            role: 'vitrine_imposte',
          );
        }

        // 2. Fixed Left Panel
        final curX0 = leftOriginX;
        final fixedLeft = _GlassPanel(
          rect: Rect.fromLTWH(
            curX0,
            bottomTopY,
            displayFixedW,
            displayBottomH,
          ),
          widthMm: fixedWidth,
          heightMm: doorHeight,
          role: 'vitrine_fixe_left',
        );

        // 3. Left Door
        final curX1 = curX0 + displayFixedW + gap;
        final doorLeft = _GlassPanel(
          rect: Rect.fromLTWH(
            curX1,
            bottomTopY,
            displayDoorW,
            displayBottomH,
          ),
          widthMm: doorWidth,
          heightMm: doorHeight,
          role: 'vitrine_door_left',
        );
        doorLeft.ensureDoorHinges(hingeSide: 'left');
        doorLeft.holes.addAll([
          _GlassHole(
            xMm: doorWidth - 60,
            yMm: doorHeight / 2 - 150,
            diameterMm: _holeDiameterMm,
            purpose: 'handle_top',
          ),
          _GlassHole(
            xMm: doorWidth - 60,
            yMm: doorHeight / 2 + 150,
            diameterMm: _holeDiameterMm,
            purpose: 'handle_bottom',
          ),
        ]);

        // 4. Right Door
        final curX2 = curX1 + displayDoorW + gap;
        final doorRight = _GlassPanel(
          rect: Rect.fromLTWH(
            curX2,
            bottomTopY,
            displayDoorW,
            displayBottomH,
          ),
          widthMm: doorWidth,
          heightMm: doorHeight,
          role: 'vitrine_door_right',
        );
        doorRight.ensureDoorHinges(hingeSide: 'right');
        doorRight.holes.addAll([
          _GlassHole(
            xMm: 60,
            yMm: doorHeight / 2 - 150,
            diameterMm: _holeDiameterMm,
            purpose: 'handle_top',
          ),
          _GlassHole(
            xMm: 60,
            yMm: doorHeight / 2 + 150,
            diameterMm: _holeDiameterMm,
            purpose: 'handle_bottom',
          ),
        ]);

        // 5. Fixed Right Panel
        final curX3 = curX2 + displayDoorW + gap;
        final fixedRight = _GlassPanel(
          rect: Rect.fromLTWH(
            curX3,
            bottomTopY,
            displayFixedW,
            displayBottomH,
          ),
          widthMm: fixedWidth,
          heightMm: doorHeight,
          role: 'vitrine_fixe_right',
        );

        _panels.clear();
        _panels.addAll([
          fixedLeft,
          doorLeft,
          doorRight,
          fixedRight,
          if (impostePanel != null) impostePanel,
        ]);
        _selectedPanelIndex = 1;
      } else {
        _overallDrawingRect = null;
        final screenCenter = _canvasSize == Size.zero
            ? const Offset(250, 200)
            : _canvasSize.center(Offset.zero);
        final displayW = 200.0;
        final displayH = 260.0;
        final panel = _GlassPanel(
          rect: Rect.fromCenter(
            center: screenCenter,
            width: displayW,
            height: displayH,
          ),
          widthMm: defaultW,
          heightMm: defaultH,
          role: code == 'paroi_fixe' ? 'fixed' : 'door',
        );
        if (code != 'paroi_fixe') {
          panel.ensureDoorHinges(hingeSide: 'left');
          panel.holes.addAll([
            _GlassHole(
              xMm: defaultW - 50,
              yMm: defaultH / 2 - 100,
              diameterMm: _holeDiameterMm,
              purpose: 'handle_top',
            ),
            _GlassHole(
              xMm: defaultW - 50,
              yMm: defaultH / 2 + 100,
              diameterMm: _holeDiameterMm,
              purpose: 'handle_bottom',
            ),
          ]);
        }
        _panels.clear();
        _panels.add(panel);
        _selectedPanelIndex = 0;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'تم تطبيق النظام بنجاح: ${sys['title_ar']}',
            'Système appliqué avec succès',
            'System applied successfully',
          ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildSideDraggableToolbar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () =>
                  setState(() => _sideToolbarExpanded = !_sideToolbarExpanded),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  _sideToolbarExpanded
                      ? Icons.menu_open_rounded
                      : Icons.menu_rounded,
                  size: 20,
                  color: Colors.cyan.shade800,
                ),
              ),
            ),
            if (_sideToolbarExpanded) ...[
              const Divider(height: 10),
              Draggable<String>(
                data: 'tool_hole',
                feedback: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.circle_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                child: Tooltip(
                  message: _tr(
                    'سحب أو نقر لإضافة ثقب (قطر: ${_holeDiameterMm.toStringAsFixed(0)} مم)',
                    'Glisser ou cliquer pour ajouter un trou',
                    'Drag or tap to add hole',
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _showQuickHoleMenu,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle_outlined,
                            color: Colors.deepOrange.shade700,
                            size: 22,
                          ),
                          Text(
                            'Ø${_holeDiameterMm.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Draggable<String>(
                data: 'tool_hinge',
                feedback: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.door_sliding_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                child: Tooltip(
                  message: _tr(
                    'سحب لإضافة مفصلة إلى الباب',
                    'Glisser pour ajouter une charnière',
                    'Drag to add hinge',
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      _addExtraHinge();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.door_sliding_outlined,
                            color: Colors.blueGrey.shade800,
                            size: 22,
                          ),
                          Text(
                            _tr('مفصل', 'Charn.', 'Hinge'),
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Draggable<String>(
                data: 'tool_handle',
                feedback: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.pan_tool_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                child: Tooltip(
                  message: _tr(
                    'سحب أو نقر لاختيار مقبض من قاعدة البيانات',
                    'Glisser ou cliquer pour choisir une poignée',
                    'Drag or tap to pick handle',
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _showDatabaseHandlesPicker,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.pan_tool_outlined,
                            color: Colors.teal.shade800,
                            size: 22,
                          ),
                          Text(
                            _tr('مقبض', 'Poignée', 'Handle'),
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Tooltip(
                message: _tr(
                  'تطبيق ثقوب متناظرة على الزوايا الـ 4',
                  '4 coins symétriques',
                  '4 corner holes',
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _apply4CornerHoles(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.grid_view_rounded,
                      color: Colors.indigo,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Tooltip(
                message: _tr(
                  'الأنظمة الجاهزة بصورها',
                  'Systèmes prêts visuels',
                  'Preset Ready Systems',
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _showPresetSystemsGallery,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.dashboard_customize_rounded,
                          color: Colors.cyan.shade800,
                          size: 22,
                        ),
                        Text(
                          _tr('جاهز', 'Prêt', 'Ready'),
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.cyan.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showQuickHoleMenu() {
    if (_refuseWhenKitLocked()) return;
    const presets = [2.0, 4.0, 10.0, 20.0, 30.0, 45.0];
    final customDiameter = TextEditingController(
      text: presets.contains(_holeDiameterMm)
          ? ''
          : _holeDiameterMm.toStringAsFixed(0),
    );
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setMenuState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.adjust_rounded, color: Colors.deepOrange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    _tr('خيارات الثقوب', 'Options des trous', 'Hole Options'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _tr(
                  'اختر القطر المفضل:',
                  'Diamètre souhaité :',
                  'Select diameter:',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...[2.0, 4.0, 10.0, 20.0, 30.0, 45.0].map((d) {
                    final isSel = _holeDiameterMm == d;
                    return ChoiceChip(
                      label: Text('${d.toStringAsFixed(0)} mm'),
                      selected: isSel,
                      selectedColor: Colors.deepOrange.shade100,
                      onSelected: (_) {
                        customDiameter.text = '';
                        setMenuState(() => _holeDiameterMm = d);
                        setState(() => _holeDiameterMm = d);
                      },
                    );
                  }),
                  // Any other diameter, typed directly.
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: customDiameter,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        LengthLimitingTextInputFormatter(5),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: _tr('قطر آخر', 'Autre Ø', 'Other Ø'),
                        suffixText: 'mm',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (text) {
                        final value = _parseMillimeters(text);
                        if (value == null || value <= 0 || value > 200) return;
                        setMenuState(() => _holeDiameterMm = value);
                        setState(() => _holeDiameterMm = value);
                      },
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (_panels.isNotEmpty) {
                    final p = _panels[_selectedPanelIndex ?? 0];
                    _pushHistory();
                    setState(() {
                      p.holes.add(
                        _GlassHole(
                          xMm: p.widthMm / 2,
                          yMm: p.heightMm / 2,
                          diameterMm: _holeDiameterMm,
                          purpose:
                              'custom_${DateTime.now().microsecondsSinceEpoch}',
                        ),
                      );
                    });
                  }
                },
                icon: const Icon(Icons.add_circle_outline),
                label: Text(
                  _tr(
                    'إضافة ثقب في مركز اللوح',
                    'Ajouter trou au centre',
                    'Add hole at center',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _apply4CornerHoles();
                },
                icon: const Icon(Icons.grid_view_rounded, color: Colors.teal),
                label: Text(
                  _tr(
                    'تطبيق ثقوب متناظرة على الزوايا الـ 4',
                    '4 coins symétriques',
                    '4 corner holes',
                  ),
                  style: const TextStyle(color: Colors.teal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _sablageOffsetFromPosition(double y) {
    final target =
        _overallDrawingRect ?? (_panels.isEmpty ? null : _panels.first.rect);
    if (target == null) return 0.0;
    final heightMm = _overallHeightMm;
    if (heightMm <= 0 || target.height <= 0) return 0.0;
    final scale = target.height / heightMm;
    return ((y - target.top) / scale)
        .clamp(0.0, math.max(0.0, heightMm - _sablageBandWidth()))
        .toDouble();
  }

  double get _overallWidthMm {
    if (_overallWidthMmValue != null && _overallWidthMmValue! > 0) {
      return _overallWidthMmValue!;
    }
    if (_panels.isNotEmpty) {
      if (_isSlidingStraight) {
        final doors = _panels.where((p) => p.isDoor);
        final fixeds = _panels.where((p) => !p.isDoor);
        if (doors.isNotEmpty && fixeds.isNotEmpty) {
          return doors.first.widthMm +
              fixeds.first.widthMm -
              _fixedWidthCompensation();
        }
      }
      return _panels.map((panel) => panel.widthMm).fold(0.0, (a, b) => a + b);
    }
    return 1000.0;
  }

  double get _overallHeightMm {
    if (_overallHeightMmValue != null && _overallHeightMmValue! > 0) {
      return _overallHeightMmValue!;
    }
    if (_panels.isNotEmpty) {
      return _panels.map((panel) => panel.heightMm).reduce(math.max);
    }
    return 2000.0;
  }

  void _addSablageBand(double offsetMm) {
    final width = _sablageBandWidth();
    final height = _overallHeightMm;
    if (height <= 0) return;
    _pushHistory();
    setState(() {
      _sablageBands.add(
        _SablageBand(
          offsetMm: offsetMm
              .clamp(0.0, math.max(0.0, height - width))
              .toDouble(),
          widthMm: width,
        ),
      );
      _draftSablageOffsetMm = null;
    });
  }

  void _applySelectedWorkType(GlassWorkType type) {
    final selectedIndex = _selectedPanelIndex;
    if (selectedIndex == null || selectedIndex >= _panels.length) {
      setState(() {
        _workType = type;
      });
      _loadSystemRules();
      return;
    }

    final selectedPanel = _panels[selectedIndex];
    final selectedRect = selectedPanel.rect;
    if (type == GlassWorkType.slidingShowerCabin) {
      final practicalWidth = selectedPanel.widthMm;
      if (_doorWidth() >= practicalWidth) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'عرض الباب يجب أن يكون أصغر من العرض العملي للكابين.',
                'La largeur de la porte doit être inférieure à la largeur pratique de la cabine.',
                'The door width must be smaller than the cabin practical width.',
              ),
            ),
          ),
        );
        return;
      }
    }

    _pushHistory();
    setState(() {
      _workType = type;
      if (type == GlassWorkType.slidingShowerCabin) {
        _overallDrawingRect = selectedRect;
        _overallWidthMmValue = selectedPanel.widthMm;
        _overallHeightMmValue = selectedPanel.heightMm;
        _setDefaultSlidingDoorWidth(selectedPanel.widthMm);
        _applySlidingLayout();
        return;
      }

      _overallDrawingRect = null;
      _overallWidthMmValue = null;
      _overallHeightMmValue = null;
      if (type == GlassWorkType.vitrineDoubleDoor) {
        const gap = 6.0;
        final panelWidth = math.max(1.0, selectedRect.width - gap) / 2;
        final widthMm = selectedPanel.widthMm > 0
            ? selectedPanel.widthMm / 2
            : panelWidth;
        final heightMm = selectedPanel.heightMm > 0
            ? selectedPanel.heightMm
            : selectedRect.height;
        _panels
          ..clear()
          ..addAll([
            _GlassPanel(
              rect: Rect.fromLTWH(
                selectedRect.left,
                selectedRect.top,
                panelWidth,
                selectedRect.height,
              ),
              widthMm: widthMm,
              heightMm: heightMm,
              role: 'vitrine_left',
            ),
            _GlassPanel(
              rect: Rect.fromLTWH(
                selectedRect.left + panelWidth + gap,
                selectedRect.top,
                panelWidth,
                selectedRect.height,
              ),
              widthMm: widthMm,
              heightMm: heightMm,
              role: 'vitrine_right',
            ),
          ]);
        _overallWidthMmValue = widthMm * 2;
        _overallHeightMmValue = heightMm;
      } else {
        final widthMm = selectedPanel.widthMm > 0
            ? selectedPanel.widthMm
            : selectedRect.width;
        final heightMm = selectedPanel.heightMm > 0
            ? selectedPanel.heightMm
            : selectedRect.height;
        _panels
          ..clear()
          ..add(
            _GlassPanel(
              rect: selectedRect,
              widthMm: widthMm,
              heightMm: heightMm,
            ),
          );
        _overallWidthMmValue = widthMm;
        _overallHeightMmValue = heightMm;
      }
      _selectedPanelIndex = 0;
    });
    _loadSystemRules();
  }

  double? _parseMillimeters(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  Rect _rectForMeasurement(double widthMm, double heightMm, {Rect? anchor}) {
    final availableSize = _canvasSize == Size.zero
        ? MediaQuery.sizeOf(context)
        : _canvasSize;
    final maxWidth = (availableSize.width - 110).clamp(120.0, 700.0).toDouble();
    final maxHeight = (availableSize.height - 90)
        .clamp(120.0, 700.0)
        .toDouble();
    final scale = <double>[
      1.0,
      maxWidth / widthMm,
      maxHeight / heightMm,
    ].reduce((a, b) => a < b ? a : b);
    final width = widthMm * scale;
    final height = heightMm * scale;
    final center = anchor?.center ?? availableSize.center(Offset.zero);
    final left = (center.dx - width / 2)
        .clamp(55.0, math.max(55.0, availableSize.width - width - 55.0))
        .toDouble();
    final top = (center.dy - height / 2)
        .clamp(44.0, math.max(44.0, availableSize.height - height - 16.0))
        .toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  Future<void> _editMeasurements({bool focusHeight = false}) async {
    final editOverall = _isSlidingStraight;
    if (editOverall) _setDefaultSlidingDoorWidth(_overallWidthMm);
    final doorWidthDraft = editOverall
        ? TextEditingController(text: _doorWidth().toStringAsFixed(0))
        : null;
    late final List<_GlassMeasurementDraft> drafts;
    if (editOverall) {
      drafts = [
        _GlassMeasurementDraft(
          width: _overallWidthMm > 0 ? _overallWidthMm : null,
          height: _overallHeightMm > 0 ? _overallHeightMm : null,
        ),
      ];
    } else if (_panels.isEmpty) {
      drafts = [
        _GlassMeasurementDraft(
          width: _overallWidthMmValue ?? 1000.0,
          height: _overallHeightMmValue ?? 2000.0,
        ),
      ];
    } else {
      drafts = _panels
          .map(
            (panel) => _GlassMeasurementDraft(
              width: panel.widthMm,
              height: panel.heightMm,
            ),
          )
          .toList();
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final screenWidth = MediaQuery.sizeOf(context).width;
            final compact = screenWidth < 600.0;
            final dialogWidth = (screenWidth - 80.0)
                .clamp(240.0, 520.0)
                .toDouble();

            void submit() {
              final valid = drafts.every((draft) {
                final width = _parseMillimeters(draft.widthController.text);
                final height = _parseMillimeters(draft.heightController.text);
                return width != null &&
                    height != null &&
                    width > 0 &&
                    height > 0;
              });
              final overallWidth = editOverall
                  ? _parseMillimeters(drafts.first.widthController.text)
                  : null;
              final doorWidth = editOverall
                  ? _parseMillimeters(doorWidthDraft!.text)
                  : null;
              final validDoorWidth =
                  !editOverall ||
                  (overallWidth != null &&
                      doorWidth != null &&
                      doorWidth > 0 &&
                      doorWidth < overallWidth &&
                      overallWidth - doorWidth + _fixedWidthCompensation() > 0);
              if (!valid || drafts.isEmpty || !validDoorWidth) {
                setDialogState(
                  () => error = _tr(
                    editOverall
                        ? 'أدخل قياسات صحيحة، ويجب أن يكون عرض الباب أصغر من العرض الإجمالي.'
                        : 'أدخل قياسات صحيحة لكل القطع.',
                    editOverall
                        ? 'Saisissez des mesures valides ; la porte doit être moins large que la largeur totale.'
                        : 'Saisissez des mesures valides pour chaque panneau.',
                    editOverall
                        ? 'Enter valid measurements; the door must be narrower than the overall width.'
                        : 'Enter valid measurements for every panel.',
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            }

            final doorWidthFocus = FocusNode();

            TextField measurementField(
              TextEditingController controller,
              String label, {
              FocusNode? focusNode,
              FocusNode? nextFocusNode,
              ValueChanged<String>? onChanged,
              bool autofocus = false,
              TextInputAction textInputAction = TextInputAction.next,
            }) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                textInputAction: textInputAction,
                onSubmitted: (_) => submit(),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: label,
                  suffixText: 'mm',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (val) {
                  onChanged?.call(val);
                  if (val.length >= 4 && nextFocusNode != null) {
                    nextFocusNode.requestFocus();
                  }
                },
              );
            }

            final overallWidth = _parseMillimeters(
              drafts.first.widthController.text,
            );
            final doorWidth = doorWidthDraft == null
                ? null
                : _parseMillimeters(doorWidthDraft.text);
            final fixedWidth = overallWidth == null || doorWidth == null
                ? null
                : overallWidth - doorWidth + _fixedWidthCompensation();

            return AlertDialog(
              title: Text(
                _tr(
                  'تعديل القياسات',
                  'Modifier les dimensions',
                  'Edit dimensions',
                ),
              ),
              content: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (editOverall) ...[
                        measurementField(
                          doorWidthDraft!,
                          _tr('عرض الباب', 'Largeur de la porte', 'Door width'),
                          focusNode: doorWidthFocus,
                          nextFocusNode: drafts.first.widthFocus,
                          autofocus: !focusHeight,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) {
                            _doorWidthCustomized = true;
                            setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            fixedWidth == null
                                ? _tr(
                                    'أدخل عرض الباب لحساب عرض الثابت.',
                                    'Saisissez la largeur de la porte pour calculer le fixe.',
                                    'Enter the door width to calculate the fixed panel.',
                                  )
                                : _tr(
                                    'عرض الثابت المحسوب: ${fixedWidth.toStringAsFixed(0)} مم',
                                    'Largeur du fixe calculée : ${fixedWidth.toStringAsFixed(0)} mm',
                                    'Calculated fixed width: ${fixedWidth.toStringAsFixed(0)} mm',
                                  ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      for (var index = 0; index < drafts.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: compact
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    measurementField(
                                      drafts[index].widthController,
                                      _tr(
                                        editOverall
                                            ? 'العرض الإجمالي'
                                            : 'العرض ${index + 1}',
                                        editOverall
                                            ? 'Largeur totale'
                                            : 'Largeur ${index + 1}',
                                        editOverall
                                            ? 'Overall width'
                                            : 'Width ${index + 1}',
                                      ),
                                      focusNode: drafts[index].widthFocus,
                                      nextFocusNode: drafts[index].heightFocus,
                                      autofocus:
                                          index == 0 &&
                                          !focusHeight &&
                                          (!editOverall ||
                                              doorWidthDraft == null),
                                      textInputAction: TextInputAction.next,
                                      onChanged: editOverall
                                          ? (_) {
                                              if (!_doorWidthCustomized) {
                                                final width = _parseMillimeters(
                                                  drafts[index]
                                                      .widthController
                                                      .text,
                                                );
                                                if (width != null &&
                                                    width > 0) {
                                                  doorWidthDraft!.text =
                                                      _defaultSlidingDoorWidth(
                                                        width,
                                                      ).toStringAsFixed(0);
                                                }
                                              }
                                              setDialogState(() {});
                                            }
                                          : null,
                                    ),
                                    const SizedBox(height: 8),
                                    measurementField(
                                      drafts[index].heightController,
                                      _tr(
                                        'الطول ${index + 1}',
                                        'Hauteur ${index + 1}',
                                        'Height ${index + 1}',
                                      ),
                                      focusNode: drafts[index].heightFocus,
                                      nextFocusNode: index + 1 < drafts.length
                                          ? drafts[index + 1].widthFocus
                                          : null,
                                      autofocus: index == 0 && focusHeight,
                                      textInputAction:
                                          index == drafts.length - 1
                                          ? TextInputAction.done
                                          : TextInputAction.next,
                                    ),
                                    if (drafts.length > 1)
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: IconButton(
                                          tooltip: _tr(
                                            'حذف القياس',
                                            'Supprimer',
                                            'Delete',
                                          ),
                                          onPressed: () {
                                            setDialogState(() {
                                              drafts[index].dispose();
                                              drafts.removeAt(index);
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: measurementField(
                                        drafts[index].widthController,
                                        _tr(
                                          editOverall
                                              ? 'العرض الإجمالي'
                                              : 'العرض ${index + 1}',
                                          editOverall
                                              ? 'Largeur totale'
                                              : 'Largeur ${index + 1}',
                                          editOverall
                                              ? 'Overall width'
                                              : 'Width ${index + 1}',
                                        ),
                                        focusNode: drafts[index].widthFocus,
                                        nextFocusNode:
                                            drafts[index].heightFocus,
                                        autofocus:
                                            index == 0 &&
                                            !focusHeight &&
                                            (!editOverall ||
                                                doorWidthDraft == null),
                                        textInputAction: TextInputAction.next,
                                        onChanged: editOverall
                                            ? (_) {
                                                if (!_doorWidthCustomized) {
                                                  final width =
                                                      _parseMillimeters(
                                                        drafts[index]
                                                            .widthController
                                                            .text,
                                                      );
                                                  if (width != null &&
                                                      width > 0) {
                                                    doorWidthDraft!.text =
                                                        _defaultSlidingDoorWidth(
                                                          width,
                                                        ).toStringAsFixed(0);
                                                  }
                                                }
                                                setDialogState(() {});
                                              }
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: measurementField(
                                        drafts[index].heightController,
                                        _tr(
                                          'الطول ${index + 1}',
                                          'Hauteur ${index + 1}',
                                          'Height ${index + 1}',
                                        ),
                                        focusNode: drafts[index].heightFocus,
                                        nextFocusNode: index + 1 < drafts.length
                                            ? drafts[index + 1].widthFocus
                                            : null,
                                        autofocus: index == 0 && focusHeight,
                                        textInputAction:
                                            index == drafts.length - 1
                                            ? TextInputAction.done
                                            : TextInputAction.next,
                                      ),
                                    ),
                                    if (drafts.length > 1)
                                      IconButton(
                                        tooltip: _tr(
                                          'حذف القياس',
                                          'Supprimer',
                                          'Delete',
                                        ),
                                        onPressed: () {
                                          setDialogState(() {
                                            drafts[index].dispose();
                                            drafts.removeAt(index);
                                          });
                                        },
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                  ],
                                ),
                        ),
                      if (error != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (!editOverall)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () => setDialogState(
                              () => drafts.add(_GlassMeasurementDraft()),
                            ),
                            icon: const Icon(Icons.add),
                            label: Text(
                              _tr(
                                'إضافة قياس',
                                'Ajouter une mesure',
                                'Add measurement',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
                ),
                FilledButton(
                  onPressed: submit,
                  child: Text(_tr('موافق', 'OK', 'OK')),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _pushHistory();
      setState(() {
        if (editOverall) {
          final width = _parseMillimeters(drafts.first.widthController.text)!;
          final height = _parseMillimeters(drafts.first.heightController.text)!;
          final doorWidth = _parseMillimeters(doorWidthDraft!.text)!;
          _doorWidthController.text = doorWidth.toStringAsFixed(0);
          _overallDrawingRect = _rectForMeasurement(
            width,
            height,
            anchor:
                _overallDrawingRect ??
                (_panels.isEmpty ? null : _panels.first.rect),
          );
          _overallWidthMmValue = width;
          _overallHeightMmValue = height;
          _applySlidingLayout();
          return;
        }
        final updated = <_GlassPanel>[];
        for (var index = 0; index < drafts.length; index++) {
          final width = _parseMillimeters(drafts[index].widthController.text)!;
          final height = _parseMillimeters(
            drafts[index].heightController.text,
          )!;
          final oldPanel = index < _panels.length ? _panels[index] : null;
          updated.add(
            _GlassPanel(
              rect: _rectForMeasurement(width, height, anchor: oldPanel?.rect),
              widthMm: width,
              heightMm: height,
              role: oldPanel?.role ?? 'panel',
              holes: (oldPanel?.holes ?? const [])
                  .map(
                    (h) => _GlassHole(
                      xMm: h.xMm.clamp(0.0, width).toDouble(),
                      yMm: h.yMm.clamp(0.0, height).toDouble(),
                      diameterMm: h.diameterMm,
                      purpose: h.purpose,
                    ),
                  )
                  .toList(),
            ),
          );
        }
        _panels
          ..clear()
          ..addAll(updated);
        _overallWidthMmValue = updated
            .map((p) => p.widthMm)
            .fold<double>(0.0, (a, b) => a + b);
        _overallHeightMmValue = updated.map((p) => p.heightMm).reduce(math.max);
        _selectedPanelIndex = updated.isEmpty ? null : 0;
      });
    }
    // showDialog completes as soon as Navigator.pop is called, while the
    // closing route can still paint its TextFields for a few frames. Disposing
    // their controllers here caused the Windows red error screen (a
    // TextEditingController was used after being disposed). Once the fields
    // unmount they remove their listeners, and these short-lived controllers
    // become collectible with the drafts.
  }

  Map<String, dynamic> _buildManufacturingPayload() {
    final area = _panels.fold<double>(
      0,
      (sum, panel) => sum + (panel.widthMm / 1000) * (panel.heightMm / 1000),
    );

    return {
      'type': 'tempered_glass_work',
      'workType': _workType.name,
      'workTypeLabel': _workTypeLabel(_workType),
      'systemCode': _currentSystemCode,
      'systemName': _currentSystemName,
      'kitId': _selectedKit?['id'],
      'kitCode': _selectedKit?['code'],
      'kitName': _selectedKit?['name'],
      'glassType': _glassType,
      'glassTypeLabel': _glassTypeLabel(_glassType),
      'glassTempered': _glassTempered,
      'edgeFinish': _edgeFinish,
      'edgeFinishLabel': _edgeFinishLabel(_edgeFinish),
      'holeDimensionMode': _holeDimensionMode.name,
      'holeDimensionModeLabel': _holeDimensionReferenceLabel(),
      'selectedAccessories': _selectedAccessories.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      'glassThicknessMm': _glassThicknessMm,
      'overallWidthMm': _overallWidthMm,
      'overallHeightMm': _overallHeightMm,
      'widthMm': _panels.isNotEmpty ? _panels.first.widthMm : _overallWidthMm,
      'heightMm': _panels.isNotEmpty
          ? _panels.first.heightMm
          : _overallHeightMm,
      'drawingVersion': 1,
      'showProfiles': _showProfiles,
      'hardwareColor': _hardwareColor,
      'profileItems': Map<String, int>.from(_profileItems),
      'gasketItems': Map<String, int>.from(_gasketItems),
      'slidingRule': _isSlidingStraight
          ? {
              'drawnWidthMm': _overallWidthMm,
              'practicalWidthMm': _overallWidthMm,
              'doorWidthMm': _doorWidth(),
              'fixedWidthMm':
                  _overallWidthMm - _doorWidth() + _fixedWidthCompensation(),
              'workshopCompensationMm': _workshopCompensation(),
              'fixedWidthIncreaseMm': _fixedWidthCompensation(),
              'doorOnLeft': _doorOnLeft,
            }
          : null,
      'sablageBands': _sablageBands
          .map((band) => {'offsetMm': band.offsetMm, 'widthMm': band.widthMm})
          .toList(),
      'sablageRegions': _sablageRegions
          .map((region) => region.toMap())
          .toList(),
      'sablageMode': _sablageMode.name,
      'sablageOptions': {
        'transparentBandWidthMm': _number(
          _sablageTransparentWidthController,
          _sablageBandWidth(),
        ),
        'rangeMode': _sablageRangeMode,
        'fromBottom': _sablageFromBottom,
        'count': int.tryParse(_sablageCountController.text.trim()) ?? 0,
        'startMm': _number(_sablageStartController, 0),
        'endMm': _number(_sablageEndController, _overallHeightMm),
      },
      'drawingPanels': _panels
          .map(
            (panel) => {
              'left': panel.rect.left,
              'top': panel.rect.top,
              'width': panel.rect.width,
              'height': panel.rect.height,
              'widthMm': panel.widthMm,
              'heightMm': panel.heightMm,
              'role': panel.role,
              'holes': panel.holes
                  .map(
                    (hole) => {
                      'xMm': hole.xMm,
                      'yMm': hole.yMm,
                      'diameterMm': hole.diameterMm,
                      'purpose': hole.purpose,
                    },
                  )
                  .toList(),
              'hinges': panel.hinges.map((h) => h.toMap()).toList(),
            },
          )
          .toList(),
      'items': _panels
          .asMap()
          .entries
          .map(
            (entry) => {
              'id':
                  'glass_panel_${DateTime.now().microsecondsSinceEpoch}_${entry.key}',
              'widthMm': entry.value.widthMm,
              'heightMm': entry.value.heightMm,
              'thicknessMm': _glassThicknessMm,
              'glassType': _glassType,
              'glassTypeLabel': _glassTypeLabel(_glassType),
              'tempered': _glassTempered,
              'edgeFinish': _edgeFinish,
              'edgeFinishLabel': _edgeFinishLabel(_edgeFinish),
              'role': entry.value.role,
              'holes': entry.value.holes
                  .map(
                    (hole) => {
                      'xMm': hole.xMm,
                      'yMm': hole.yMm,
                      'diameterMm': hole.diameterMm,
                      'purpose': hole.purpose,
                    },
                  )
                  .toList(),
              'quantity': 1,
              'areaSqm':
                  (entry.value.widthMm / 1000) * (entry.value.heightMm / 1000),
              'pricePerSqm': 0.0,
              'unitPrice': 0.0,
              'totalPrice': 0.0,
            },
          )
          .toList(),
      'itemsCount': _panels.length,
      'totalQuantity': _panels.length,
      'grandTotalAreaSqm': area,
      'grandTotalPrice': 0.0,
    };
  }

  /// Lists holes that break tempered-glass limits and lets the user go back
  /// to fix them. Returns true to continue to the manufacturing sheet.
  Future<bool> _confirmHoleIssues() async {
    final issues = findTemperedHoleIssues(
      thicknessMm: _glassThicknessMm,
      panels: [
        for (final panel in _panels)
          (
            widthMm: panel.widthMm,
            heightMm: panel.heightMm,
            holes: [
              for (final hole in panel.holes)
                (
                  xMm: hole.xMm,
                  yMm: hole.yMm,
                  diameterMm: hole.diameterMm,
                  purpose: hole.purpose,
                ),
            ],
          ),
      ],
    );
    if (issues.isEmpty) return true;

    String describe(TemperedHoleIssue issue) {
      final panel = '${_tr('لوح', 'Panneau', 'Panel')} ${issue.panelIndex + 1}';
      final value = issue.valueMm.toStringAsFixed(0);
      final minimum = issue.minimumMm.toStringAsFixed(0);
      final problem = switch (issue.kind) {
        'diameter' => _tr(
          'قطر الثقب $value مم أصغر من سماكة الزجاج ($minimum مم)',
          'diamètre $value mm inférieur à l’épaisseur ($minimum mm)',
          'hole diameter $value mm below the glass thickness ($minimum mm)',
        ),
        'edge' => _tr(
          'المسافة إلى حافة الزجاج $value مم (الحد الأدنى $minimum مم)',
          'distance au bord $value mm (minimum $minimum mm)',
          'distance to the glass edge $value mm (minimum $minimum mm)',
        ),
        _ => _tr(
          'المسافة بين الثقبين $value مم (الحد الأدنى $minimum مم)',
          'distance entre trous $value mm (minimum $minimum mm)',
          'distance between holes $value mm (minimum $minimum mm)',
        ),
      };
      return '$panel – ${issue.purpose}: $problem';
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
        title: Text(
          _tr(
            'ثقوب قد تكسر الزجاج عند التقسية',
            'Trous risquant de casser le verre à la trempe',
            'Holes that may break the glass when tempering',
          ),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final issue in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• ${describe(issue)}'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _tr('متابعة رغم ذلك', 'Continuer quand même', 'Continue anyway'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              _tr('رجوع للتعديل', 'Revenir corriger', 'Go back and fix'),
            ),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<void> _showManufacturingSheet() async {
    if (_panels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'ارسم في مساحة الرسم أولاً.',
              'Dessinez d’abord dans la zone de dessin.',
              'Draw in the canvas first.',
            ),
          ),
        ),
      );
      return;
    }

    if (!await _confirmHoleIssues()) return;
    if (!mounted) return;

    final payload = _buildManufacturingPayload();
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _GlassManufacturingSheet(
          payload: payload,
          panels: _panels.map((panel) => panel.copy()).toList(),
          drawingCanvasSize: _canvasSize,
          sablageBands: List.of(_sablageBands),
          sablageRegions: List.of(_sablageRegions),
          sablageBandWidthMm: _sablageBandWidth(),
          overallHeightMm: _overallHeightMm,
          sablageMode: _sablageMode,
          workTypeLabel: _workTypeLabel(_workType),
          allOrderGlassPayloads: widget.allOrderGlassPayloads,
          clientName: widget.clientName,
          orderNumber: widget.orderNumber,
        ),
      ),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  Future<void> _showWorkTypeMenu(BuildContext buttonContext) async {
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    RelativeRect position;
    if (renderBox != null && renderBox.hasSize && overlay != null) {
      position = RelativeRect.fromRect(
        Rect.fromPoints(
          renderBox.localToGlobal(Offset.zero, ancestor: overlay),
          renderBox.localToGlobal(
            renderBox.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );
    } else {
      position = const RelativeRect.fromLTRB(100, 100, 100, 100);
    }

    if (_glassSystems.isEmpty) {
      final systems = await _db.getTemperedGlassSystems(onlyActive: true);
      if (mounted) setState(() => _glassSystems = systems);
    }

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    final selected = await showMenu<Map<String, dynamic>>(
      context: context,
      position: position,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<Map<String, dynamic>>(
          value: const {'code': '__preset_gallery__'},
          height: 40,
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_mosaic_rounded,
                size: 20,
                color: Colors.cyan.shade800,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tr(
                    'معاينة الأنظمة الجاهزة (صور ورسومات)',
                    'Galerie visuelle des systèmes prêts',
                    'Visual ready-made systems gallery',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: Colors.cyan.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<Map<String, dynamic>>(
          enabled: false,
          height: 30,
          child: Text(
            _tr('أنظمة الزجاج المقسّى', 'Systèmes de vitrage', 'Glass Systems'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
              color: Colors.cyan.shade800,
            ),
          ),
        ),
        if (_glassSystems.isNotEmpty)
          ..._glassSystems.map((sys) {
            final name =
                lang == AppLanguage.french &&
                    (sys['name_fr'] ?? '').toString().isNotEmpty
                ? sys['name_fr']
                : (lang == AppLanguage.english &&
                          (sys['name_en'] ?? '').toString().isNotEmpty
                      ? sys['name_en']
                      : sys['name_ar'] ?? sys['code']);
            final isCurrent = _currentSystemCode == sys['code'];
            final icon = switch (sys['category']) {
              'vitrine' => Icons.storefront,
              'paroi' => Icons.crop_portrait,
              _ => Icons.shower,
            };
            return PopupMenuItem<Map<String, dynamic>>(
              value: sys,
              height: 38,
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: isCurrent ? Colors.cyan.shade800 : Colors.blueGrey,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name.toString(),
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent ? Colors.cyan.shade900 : null,
                      ),
                    ),
                  ),
                  if (isCurrent)
                    const Icon(Icons.check, size: 16, color: Colors.cyan),
                ],
              ),
            );
          })
        else
          ...GlassWorkType.values.map((type) {
            final code = switch (type) {
              GlassWorkType.slidingShowerCabin => 'coulissante',
              GlassWorkType.showerCabin => 'cabine_l',
              GlassWorkType.singleDoorShowerCabin => 'cabine_porte',
              GlassWorkType.vitrineSingleDoor => 'vitrine_1p',
              GlassWorkType.vitrineDoubleDoor => 'vitrine_2p',
              GlassWorkType.vitrineComposite => 'vitrine_composite_5p',
            };
            return PopupMenuItem<Map<String, dynamic>>(
              value: {'code': code},
              height: 38,
              child: Text(_workTypeLabel(type)),
            );
          }),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<Map<String, dynamic>>(
          value: const {'action': 'manage'},
          height: 36,
          child: Row(
            children: [
              const Icon(
                Icons.settings_outlined,
                size: 18,
                color: Colors.blueGrey,
              ),
              const SizedBox(width: 8),
              Text(
                _tr(
                  'إدارة وتعديل الأنظمة والقواعد...',
                  'Gérer les systèmes...',
                  'Manage systems & rules...',
                ),
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected != null) {
      if (selected['code'] == '__preset_gallery__') {
        await _showPresetSystemsGallery();
      } else if (selected['action'] == 'manage') {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GlassSystemsRulesScreen(db: _db)),
        );
        _loadAccessories();
      } else {
        await _selectSystem(selected);
      }
    }
  }

  Future<void> _showWorkTypeSheet([BuildContext? buttonContext]) async {
    if (buttonContext != null) {
      return _showWorkTypeMenu(buttonContext);
    }
    if (_glassSystems.isEmpty) {
      final systems = await _db.getTemperedGlassSystems(onlyActive: true);
      if (mounted) setState(() => _glassSystems = systems);
    }
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.dashboard_customize_outlined, color: Colors.cyan),
            const SizedBox(width: 8),
            Text(
              _tr(
                'أنظمة الزجاج المقسّى',
                'Systèmes de vitrage',
                'Glass Systems',
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_glassSystems.isNotEmpty)
                  ..._glassSystems.map((sys) {
                    final name =
                        lang == AppLanguage.french &&
                            (sys['name_fr'] ?? '').toString().isNotEmpty
                        ? sys['name_fr']
                        : (lang == AppLanguage.english &&
                                  (sys['name_en'] ?? '').toString().isNotEmpty
                              ? sys['name_en']
                              : sys['name_ar'] ?? sys['code']);
                    final isCurrent = _currentSystemCode == sys['code'];
                    final icon = switch (sys['category']) {
                      'vitrine' => Icons.storefront,
                      'paroi' => Icons.crop_portrait,
                      _ => Icons.shower,
                    };
                    return ListTile(
                      leading: Icon(
                        icon,
                        color: isCurrent
                            ? Colors.cyan.shade800
                            : Colors.blueGrey,
                      ),
                      title: Text(
                        name.toString(),
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCurrent ? Colors.cyan.shade900 : null,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Icon(Icons.check, color: Colors.cyan)
                          : null,
                      onTap: () => Navigator.pop(dialogCtx, sys),
                    );
                  })
                else
                  ...GlassWorkType.values.map((type) {
                    final code = switch (type) {
                      GlassWorkType.slidingShowerCabin => 'coulissante',
                      GlassWorkType.showerCabin => 'cabine_l',
                      GlassWorkType.singleDoorShowerCabin => 'cabine_porte',
                      GlassWorkType.vitrineSingleDoor => 'vitrine_1p',
                      GlassWorkType.vitrineDoubleDoor => 'vitrine_2p',
                      GlassWorkType.vitrineComposite => 'vitrine_composite_5p',
                    };
                    return ListTile(
                      title: Text(_workTypeLabel(type)),
                      onTap: () => Navigator.pop(dialogCtx, {'code': code}),
                    );
                  }),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.settings_outlined,
                    color: Colors.blueGrey,
                  ),
                  title: Text(
                    _tr(
                      'إدارة وتعديل الأنظمة والقواعد...',
                      'Gérer les systèmes...',
                      'Manage systems & rules...',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.blueGrey,
                    ),
                  ),
                  onTap: () => Navigator.pop(dialogCtx, {'action': 'manage'}),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selected != null) {
      if (selected['action'] == 'manage') {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GlassSystemsRulesScreen(db: _db)),
        );
        _loadAccessories();
      } else {
        await _selectSystem(selected);
      }
    }
  }

  Future<void> _showSablageMenu(BuildContext buttonContext) async {
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    RelativeRect position;
    if (renderBox != null && renderBox.hasSize && overlay != null) {
      position = RelativeRect.fromRect(
        Rect.fromPoints(
          renderBox.localToGlobal(Offset.zero, ancestor: overlay),
          renderBox.localToGlobal(
            renderBox.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );
    } else {
      position = const RelativeRect.fromLTRB(100, 100, 100, 100);
    }

    final hasActiveSablage =
        _sablageBands.isNotEmpty ||
        _sablageRegions.isNotEmpty ||
        _sablageMode != _SablageMode.none;

    final selected = await showMenu<String>(
      context: context,
      position: position,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<String>(
          value: 'none',
          height: 38,
          child: Row(
            children: [
              const Icon(Icons.clear, size: 19, color: Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_tr('بدون سابلاج', 'Sans sablage', 'No frosting')),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'full',
          height: 38,
          child: Row(
            children: [
              const Icon(Icons.format_color_fill, size: 19, color: Colors.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tr('تعتيم كامل (Full)', 'Sablage complet', 'Full frosting'),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'decorative',
          height: 38,
          child: Row(
            children: [
              const Icon(
                Icons.view_agenda_outlined,
                size: 19,
                color: Colors.deepOrange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tr(
                    'تعتيم ديكور (Decorative)',
                    'Sablage décoratif',
                    'Decorative frosting',
                  ),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'add_region',
          height: 38,
          child: Row(
            children: [
              Icon(
                Icons.add_box_outlined,
                size: 19,
                color: Colors.teal.shade700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tr(
                    'إضافة منطقة صابلاج...',
                    'Ajouter une zone...',
                    'Add frosting zone...',
                  ),
                  style: TextStyle(
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'draw_bands',
          height: 38,
          child: Row(
            children: [
              Icon(
                _sablageDrawingActive ? Icons.touch_app : Icons.gesture,
                size: 19,
                color: Colors.indigo,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _sablageDrawingActive
                      ? _tr(
                          'إيقاف رسم شرائط الصابلاج',
                          'Arrêter le dessin des bandes',
                          'Stop drawing frosting bands',
                        )
                      : _tr(
                          'رسم شرائط الصابلاج يدويًا',
                          'Dessiner les bandes manuellement',
                          'Draw frosting bands manually',
                        ),
                ),
              ),
            ],
          ),
        ),
        if (hasActiveSablage)
          PopupMenuItem<String>(
            value: 'clear_all',
            height: 38,
            child: Row(
              children: [
                const Icon(Icons.clear_all, size: 19, color: Colors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tr(
                      'مسح جميع مناطق الصابلاج',
                      'Effacer tout le sablage',
                      'Clear all frosting',
                    ),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (selected == null) return;
    if (selected == 'add_region') {
      setState(() => _sablageDrawingActive = false);
      await _addSablageRegion();
      return;
    }
    if (selected == 'draw_bands') {
      setState(() {
        _sablageMode = _SablageMode.decorative;
        _sablageDrawingActive = !_sablageDrawingActive;
      });
      return;
    }
    if (selected == 'clear_all') {
      _pushHistory();
      setState(() {
        _sablageMode = _SablageMode.none;
        _sablageBands.clear();
        _sablageRegions.clear();
        _sablageDrawingActive = false;
      });
      return;
    }

    _pushHistory();
    if (selected == 'none') {
      setState(() {
        _sablageMode = _SablageMode.none;
        _sablageBands.clear();
        _sablageRegions.clear();
        _sablageDrawingActive = false;
      });
    } else if (selected == 'full') {
      setState(() {
        _sablageMode = _SablageMode.full;
        _sablageBands.clear();
        _sablageDrawingActive = false;
      });
    } else if (selected == 'decorative') {
      setState(() {
        _sablageMode = _SablageMode.decorative;
        _sablageDrawingActive = false;
      });
      await _editSablageOptions();
    }
  }

  Future<void> _showSablageSheet([BuildContext? buttonContext]) async {
    if (buttonContext != null) {
      return _showSablageMenu(buttonContext);
    }
    final selected = await showDialog<_SablageMode>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.brush_outlined, color: Colors.cyan),
            const SizedBox(width: 8),
            Text(
              _tr('نوع التعتيم (Sablage)', 'Type de sablage', 'Sablage type'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogCtx, _SablageMode.none),
              icon: const Icon(Icons.clear),
              label: Text(_tr('بدون سابلاج', 'Sans sablage', 'No frosting')),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogCtx, _SablageMode.full),
              icon: const Icon(Icons.format_color_fill),
              label: Text(
                _tr('تعتيم كامل', 'Sablage complet', 'Full frosting'),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogCtx, _SablageMode.decorative),
              icon: const Icon(Icons.view_agenda_outlined),
              label: Text(
                _tr('تعتيم ديكور', 'Sablage décoratif', 'Decorative frosting'),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    _pushHistory();
    if (selected == _SablageMode.none) {
      setState(() {
        _sablageMode = selected;
        _sablageBands.clear();
      });
    } else if (selected == _SablageMode.full) {
      setState(() {
        _sablageMode = selected;
        _sablageBands.clear();
      });
    } else {
      setState(() => _sablageMode = selected);
      await _editSablageOptions();
    }
  }

  void _regenerateSablageBands({
    bool keepExisting = true,
    int direction = 0, // 0: bottom, 1: top, 2: both
  }) {
    final height = _overallHeightMm;
    if (height <= 0) return;
    final opaqueWidth = _sablageBandWidth();
    final transparentWidth = _number(
      _sablageTransparentWidthController,
      opaqueWidth,
    ).clamp(0.0, double.infinity).toDouble();
    final start = _number(
      _sablageStartController,
      0.0,
    ).clamp(0.0, height).toDouble();
    final end = _number(
      _sablageEndController,
      height,
    ).clamp(0.0, height).toDouble();
    final pitch = opaqueWidth + transparentWidth;
    final count = int.tryParse(_sablageCountController.text.trim()) ?? 0;

    final newOffsets = <double>[];

    void calculateOffsets(bool fromBottom) {
      if (_sablageRangeMode) {
        final rangeStart = fromBottom ? height - end : start;
        final rangeEnd = fromBottom ? height - start : end;
        for (
          var offset = rangeStart;
          offset + opaqueWidth <= rangeEnd + 0.1;
          offset += pitch
        ) {
          if (offset >= 0 && offset + opaqueWidth <= height + 0.1) {
            newOffsets.add(offset);
          }
        }
      } else {
        for (var index = 0; index < count; index++) {
          final offset = fromBottom
              ? height - start - opaqueWidth - index * pitch
              : start + index * pitch;
          if (offset >= 0 && offset + opaqueWidth <= height + 0.1) {
            newOffsets.add(offset);
          }
        }
      }
    }

    if (direction == 2) {
      calculateOffsets(false); // top
      calculateOffsets(true); // bottom
    } else if (direction == 1) {
      calculateOffsets(false); // top
    } else {
      calculateOffsets(true); // bottom
    }

    if (!keepExisting) {
      _sablageBands.clear();
    }

    for (final offset in newOffsets) {
      if (!_sablageBands.any((b) => (b.offsetMm - offset).abs() < 1.0)) {
        _sablageBands.add(_SablageBand(offsetMm: offset, widthMm: opaqueWidth));
      }
    }
    _sablageBands.sort((a, b) => a.offsetMm.compareTo(b.offsetMm));
  }

  Future<void> _editSablageOptions() async {
    String? error;
    int direction = _sablageFromBottom ? 0 : 1; // 0: bottom, 1: top, 2: both
    bool keepExistingBands = _sablageBands.isNotEmpty;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void submit() {
            final opaque = _parseMillimeters(_sablageBandWidthController.text);
            final transparent = _parseMillimeters(
              _sablageTransparentWidthController.text,
            );
            final start = _parseMillimeters(_sablageStartController.text);
            final end = _parseMillimeters(_sablageEndController.text);
            final count = int.tryParse(_sablageCountController.text.trim());
            final valid =
                opaque != null &&
                transparent != null &&
                start != null &&
                opaque > 0 &&
                transparent >= 0 &&
                start >= 0 &&
                (!_sablageRangeMode
                    ? count != null && count > 0
                    : end != null && end > start);
            if (!valid) {
              setDialogState(
                () => error = _tr(
                  'تحقق من قيم الباندات.',
                  'Vérifiez les valeurs des bandes.',
                  'Check the band values.',
                ),
              );
              return;
            }
            Navigator.pop(dialogContext, true);
          }

          return AlertDialog(
            title: Text(
              _tr(
                'إعداد تعتيم الديكور (السابلاج)',
                'Réglage du sablage décoratif',
                'Decorative frosting settings',
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _tr(
                      'جهة تطبيق التعتيم:',
                      'Direction du sablage:',
                      'Frosting direction:',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text(_tr('من الأسفل', 'Du bas', 'From bottom')),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text(_tr('من الأعلى', 'Du haut', 'From top')),
                      ),
                      ButtonSegment(
                        value: 2,
                        label: Text(_tr('كلاهما معاً', 'Les deux', 'Both')),
                      ),
                    ],
                    selected: {direction},
                    onSelectionChanged: (set) {
                      setDialogState(() => direction = set.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sablageBandWidthController,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => submit(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _tr(
                        'عرض الباندة المعتمة',
                        'Largeur bande opaque',
                        'Opaque band width',
                      ),
                      suffixText: 'mm',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sablageTransparentWidthController,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => submit(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _tr(
                        'عرض الباندة الشفافة',
                        'Largeur bande transparente',
                        'Transparent band width',
                      ),
                      suffixText: 'mm',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: _sablageRangeMode,
                    onChanged: (value) => setDialogState(
                      () => _sablageRangeMode = value ?? false,
                    ),
                    title: Text(
                      _tr(
                        'عدد الباندات',
                        'Nombre de bandes',
                        'Number of bands',
                      ),
                    ),
                  ),
                  if (!_sablageRangeMode)
                    TextField(
                      controller: _sablageCountController,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => submit(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _tr('العدد', 'Nombre', 'Count'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: _sablageRangeMode,
                    onChanged: (value) =>
                        setDialogState(() => _sablageRangeMode = value ?? true),
                    title: Text(
                      _tr(
                        'نطاق القياس',
                        'Plage de mesure',
                        'Measurement range',
                      ),
                    ),
                  ),
                  TextField(
                    controller: _sablageStartController,
                    textInputAction: _sablageRangeMode
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _tr(
                        'البداية من الحافة',
                        'Début depuis le bord',
                        'Start from edge',
                      ),
                      suffixText: 'mm',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_sablageRangeMode) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sablageEndController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _tr('النهاية', 'Fin', 'End'),
                        suffixText: 'mm',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  SwitchListTile(
                    value: keepExistingBands,
                    onChanged: (val) =>
                        setDialogState(() => keepExistingBands = val),
                    title: Text(
                      _tr(
                        'الاحتفاظ بالسابلاج السابق وإضافة الجديد',
                        'Conserver le sablage existant',
                        'Keep existing frosting & append',
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (_sablageBands.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () {
                        _pushHistory();
                        setState(_sablageBands.clear);
                        Navigator.pop(dialogContext, false);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(
                        _tr(
                          'مسح كل السابلاج الحالي',
                          'Effacer tout le sablage',
                          'Clear all frosting',
                        ),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(_tr('موافق', 'OK', 'OK')),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true && mounted) {
      _pushHistory();
      setState(() {
        _sablageFromBottom = direction == 0;
        _regenerateSablageBands(
          keepExisting: keepExistingBands,
          direction: direction,
        );
      });
    }
  }

  Future<void> _addSablageRegion() async {
    var type = _SablageRegionType.full;
    var fromBottom = true;
    String? errorMessage;
    final start = TextEditingController(text: '0');
    final end = TextEditingController(
      text: _overallHeightMm.toStringAsFixed(0),
    );
    final opaque = TextEditingController(
      text: _sablageBandWidthController.text,
    );
    final clear = TextEditingController(
      text: _sablageTransparentWidthController.text,
    );
    final region = await showDialog<_SablageRegion>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final curFrom = _parseMillimeters(start.text);
          final curTo = _parseMillimeters(end.text);
          final heightDiff = (curFrom != null && curTo != null)
              ? (curTo - curFrom)
              : null;

          return AlertDialog(
            title: Text(
              _tr(
                'إضافة منطقة سابلاج',
                'Ajouter une zone de sablage',
                'Add frosting zone',
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<_SablageRegionType>(
                    value: type,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'نمط المنطقة',
                        'Motif de la zone',
                        'Zone pattern',
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: _SablageRegionType.clear,
                        child: Text(_tr('شفاف', 'Transparent', 'Clear')),
                      ),
                      DropdownMenuItem(
                        value: _SablageRegionType.full,
                        child: Text(
                          _tr(
                            'سابلاج كامل',
                            'Sablage complet',
                            'Full frosting',
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: _SablageRegionType.bands,
                        child: Text(
                          _tr(
                            'سابلاج بخطوط',
                            'Sablage par bandes',
                            'Striped frosting',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      type = value ?? type;
                      errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<bool>(
                    value: fromBottom,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'المرجع للقياس',
                        'Référence de mesure',
                        'Measurement reference',
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: true,
                        child: Text(
                          _tr(
                            'من الأسفل (الأرضية)',
                            'Depuis le bas',
                            'From bottom',
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text(
                          _tr('من الأعلى', 'Depuis le haut', 'From top'),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      fromBottom = value ?? true;
                      errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: start,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: fromBottom
                          ? _tr(
                              'البداية من الأسفل',
                              'Début depuis le bas',
                              'Start from bottom',
                            )
                          : _tr(
                              'البداية من الأعلى',
                              'Début depuis le haut',
                              'Start from top',
                            ),
                      suffixText: 'mm',
                    ),
                    onChanged: (_) => setDialogState(() => errorMessage = null),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: end,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: fromBottom
                          ? _tr(
                              'النهاية من الأسفل',
                              'Fin depuis le bas',
                              'End from bottom',
                            )
                          : _tr(
                              'النهاية من الأعلى',
                              'Fin depuis le haut',
                              'End from top',
                            ),
                      suffixText: 'mm',
                    ),
                    onChanged: (_) => setDialogState(() => errorMessage = null),
                  ),
                  if (heightDiff != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      heightDiff > 0
                          ? _tr(
                              'ارتفاع منطقة السابلاج: ${heightDiff.toStringAsFixed(0)} مم',
                              'Hauteur de la zone : ${heightDiff.toStringAsFixed(0)} mm',
                              'Zone height: ${heightDiff.toStringAsFixed(0)} mm',
                            )
                          : _tr(
                              'تنبيه: النهاية يجب أن تكون أكبر من البداية (الارتفاع حالياً: 0 مم)',
                              'Attention : la fin doit être supérieure au début (hauteur : 0 mm)',
                              'Warning: end must be greater than start (height: 0 mm)',
                            ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: heightDiff > 0
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                    ),
                  ],
                  if (type == _SablageRegionType.bands) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: opaque,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _tr(
                          'عرض الخط الصبغي',
                          'Largeur de bande sablée',
                          'Frosted band width',
                        ),
                        suffixText: 'mm',
                      ),
                      onChanged: (_) =>
                          setDialogState(() => errorMessage = null),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: clear,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _tr(
                          'عرض الفراغ الشفاف',
                          'Largeur de bande transparente',
                          'Clear gap width',
                        ),
                        suffixText: 'mm',
                      ),
                      onChanged: (_) =>
                          setDialogState(() => errorMessage = null),
                    ),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final from = _parseMillimeters(start.text);
                  final to = _parseMillimeters(end.text);
                  final band = _parseMillimeters(opaque.text) ?? 40;
                  final gap = _parseMillimeters(clear.text) ?? 40;

                  if (from == null || to == null) {
                    setDialogState(() {
                      errorMessage = _tr(
                        'يرجى إدخال قيم عددية صحيحة.',
                        'Veuillez saisir des valeurs valides.',
                        'Please enter valid numbers.',
                      );
                    });
                    return;
                  }
                  if (from < 0) {
                    setDialogState(() {
                      errorMessage = _tr(
                        'قيمة البداية لا يمكن أن تكون سالبة.',
                        'Le début ne peut pas être inférieur à 0.',
                        'Start cannot be negative.',
                      );
                    });
                    return;
                  }
                  if (to <= from) {
                    final suggested = (from + 400).toInt();
                    setDialogState(() {
                      errorMessage = _tr(
                        'النهاية ($to مم) يجب أن تكون أكبر من البداية ($from مم). مثلاً: اجعل النهاية $suggested مم لتكون المنطقة بارتفاع 400 مم.',
                        'La fin ($to mm) doit être supérieure au début ($from mm). Ex : fin $suggested mm pour une hauteur de 400 mm.',
                        'End must be greater than start. E.g. set end to $suggested mm.',
                      );
                    });
                    return;
                  }
                  if (to > _overallHeightMm) {
                    setDialogState(() {
                      errorMessage = _tr(
                        'النهاية ($to مم) تتجاوز الارتفاع الإجمالي للزجاج (${_overallHeightMm.toInt()} مم).',
                        'La fin ($to mm) dépasse la hauteur totale (${_overallHeightMm.toInt()} mm).',
                        'End exceeds total height.',
                      );
                    });
                    return;
                  }
                  if (type == _SablageRegionType.bands && band <= 0) {
                    setDialogState(() {
                      errorMessage = _tr(
                        'عرض الخط الصبغي يجب أن يكون أكبر من 0.',
                        'La largeur de bande sablée doit être supérieure à 0.',
                        'Frosted band width must be greater than 0.',
                      );
                    });
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    _SablageRegion(
                      type: type,
                      startMm: from,
                      endMm: to,
                      fromBottom: fromBottom,
                      opaqueBandMm: band,
                      clearBandMm: gap,
                    ),
                  );
                },
                child: Text(_tr('إضافة', 'Ajouter', 'Add')),
              ),
            ],
          );
        },
      ),
    );
    if (region == null || !mounted) return;
    _pushHistory();
    setState(() {
      _sablageMode = _SablageMode.decorative;
      _sablageRegions.add(region);
      _sablageRegions.sort((a, b) => a.startMm.compareTo(b.startMm));
    });
  }

  Future<void> _confirmClearDrawing() async {
    if (_panels.isEmpty &&
        _sablageBands.isEmpty &&
        _draftPanel == null &&
        _overallDrawingRect == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('مسح الرسم؟', 'Effacer le dessin ?', 'Clear drawing?')),
        content: Text(
          _tr(
            'سيتم حذف الرسم والصبلاج الحاليين.',
            'Le dessin et le sablage actuels seront supprimés.',
            'The current drawing and frosting will be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('مسح', 'Effacer', 'Clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _pushHistory();
    setState(() {
      _panels.clear();
      _holeOverrides.clear();
      _sablageBands.clear();
      _overallDrawingRect = null;
      _overallWidthMmValue = null;
      _overallHeightMmValue = null;
      _selectedPanelIndex = null;
      _drawStart = null;
      _draftPanel = null;
      _draftSablageOffsetMm = null;
      _handleCenterFromTopMm = null;
      _towelCenterFromLeftMm = null;
      _towelCenterFromTopMm = null;
      _sablageMode = _SablageMode.none;
    });
  }

  Widget _buildAccessoriesEndDrawer(BuildContext context) {
    final allowedItemIds = _systemRules
        .where(
          (r) => r['item_id'] != null && (r['is_active'] as int? ?? 1) == 1,
        )
        .map((r) => r['item_id'] as int)
        .toSet();
    final kitItemIds = _activeKitComponents
        .where((row) {
          final thickness = (row['glass_thickness_mm'] as num? ?? 0).toDouble();
          return thickness <= 0 || (thickness - _glassThicknessMm).abs() < .01;
        })
        .map((row) => (row['item_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();

    final filtered = _catalogAccessories.where((item) {
      // Services are priced by the cost table, not added as hardware.
      if (item['category'] == 'faconnage') return false;
      if (kitItemIds.isNotEmpty && !kitItemIds.contains(item['id'])) {
        return false;
      }
      if (allowedItemIds.isNotEmpty && !allowedItemIds.contains(item['id'])) {
        return false;
      }
      final matchesCat =
          _accDrawerCategory == 'all' || item['category'] == _accDrawerCategory;
      final q = _accDrawerSearch.trim().toLowerCase();
      final matchesQuery =
          q.isEmpty ||
          (item['name'] ?? '').toString().toLowerCase().contains(q) ||
          (item['notes'] ?? '').toString().toLowerCase().contains(q) ||
          (item['category_name'] ?? '').toString().toLowerCase().contains(q);
      return matchesCat && matchesQuery;
    }).toList();

    final totalCount = _selectedAccessories.values.fold(0, (a, b) => a + b);

    return Drawer(
      width: (MediaQuery.sizeOf(context).width * 0.85).clamp(320.0, 480.0),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.cyan.shade800,
              child: Row(
                children: [
                  const Icon(Icons.hardware, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr(
                            'إكسسوارات وقطاعات الزجاج',
                            'Accessoires & profilés',
                            'Accessories & Profiles',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (allowedItemIds.isNotEmpty)
                          Text(
                            _tr(
                              'مفلترة حسب قواعد النظام وسُمك الزجاج',
                              'Filtré selon les règles du système',
                              'Filtered by system rules',
                            ),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                decoration: InputDecoration(
                  hintText: _tr(
                    'بحث عن إكسسوار...',
                    'Rechercher...',
                    'Search...',
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) => setState(() => _accDrawerSearch = val),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      final isSel = _accDrawerCategory == cat;
                      final catLabel = switch (cat) {
                        'all' => _tr('الكل', 'Tous', 'All'),
                        'poignee' => _tr('المقابض', 'Poignées', 'Handles'),
                        'charniere' => _tr('المفصلات', 'Charnières', 'Hinges'),
                        'profile' => _tr(
                          'القطاعات والسكك',
                          'Profilés',
                          'Profiles',
                        ),
                        'fixation' => _tr('التثبيت', 'Fixations', 'Clamps'),
                        'joint' => _tr('الجوانات', 'Joints', 'Seals'),
                        'serrure' => _tr('الأقفال', 'Serrures', 'Locks'),
                        _ => cat,
                      };
                      return Padding(
                        padding: const EdgeInsets.only(right: 4, left: 4),
                        child: ChoiceChip(
                          selected: isSel,
                          label: Text(
                            catLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isSel ? Colors.white : null,
                            ),
                          ),
                          selectedColor: Colors.cyan.shade800,
                          onSelected: (_) =>
                              setState(() => _accDrawerCategory = cat),
                        ),
                      );
                    }).toList(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _tr(
                          'لا توجد عناصر مطابقة',
                          'Aucun élément',
                          'No items found',
                        ),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      itemBuilder: (ctx, idx) {
                        final item = filtered[idx];
                        final id = item['id'] as int;
                        final name = item['name']?.toString() ?? '';
                        final price =
                            _colorPrice(item, 0.0);
                        final unit = item['unit']?.toString() ?? 'piece';
                        final qty = _selectedAccessories[id] ?? 0;
                        final isSelected = qty > 0;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: isSelected ? 2 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.cyan.shade700
                                  : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 0.8,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${price.toStringAsFixed(0)} DZD ${unit == 'meter' ? '/m' : '/pce'}',
                                        style: TextStyle(
                                          color: Colors.cyan.shade800,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (((item['holes_count'] as num?)
                                                ?.toInt() ??
                                            0) >
                                        0)
                                      IconButton(
                                        tooltip: _tr(
                                          'وضع ثقوبه على الزجاج',
                                          'Placer ses trous sur le verre',
                                          'Place its holes on the glass',
                                        ),
                                        icon: const Icon(
                                          Icons.add_location_alt_outlined,
                                          size: 20,
                                        ),
                                        color: Colors.deepOrange.shade400,
                                        onPressed: () {
                                          _scaffoldKey.currentState
                                              ?.closeEndDrawer();
                                          _placeAccessoryOnGlass(item);
                                        },
                                      ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 20,
                                      ),
                                      color: qty > 0
                                          ? Colors.red.shade400
                                          : Colors.grey.shade300,
                                      onPressed: qty > 0
                                          ? () {
                                              _pushHistory();
                                              setState(() {
                                                if (qty == 1) {
                                                  _selectedAccessories.remove(
                                                    id,
                                                  );
                                                } else {
                                                  _selectedAccessories[id] =
                                                      qty - 1;
                                                }
                                              });
                                            }
                                          : null,
                                    ),
                                    Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$qty',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isSelected
                                              ? Colors.cyan.shade900
                                              : Colors.grey,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        size: 20,
                                      ),
                                      color: Colors.cyan.shade700,
                                      onPressed: () {
                                        _pushHistory();
                                        setState(() {
                                          _selectedAccessories[id] = qty + 1;
                                        });
                                      },
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_tr('المحدد', 'Sélectionnés', 'Selected')}: $totalCount ${_tr('عنصر', 'élém.', 'items')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.cyan.shade800,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                    ),
                    child: Text(_tr('تأكيد', 'Valider', 'Confirm')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.cyan.shade800),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.cyan.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _tableCell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontSize: 11.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Price per m² of tempered glass of the drawing's thickness from the
  /// Glass catalogue, or null when the catalogue has none.
  Future<double?> _catalogTemperedGlassRatePerSqm() async {
    try {
      final rows = await _db.readGlass();
      double? best;
      var bestScore = -1;
      for (final row in rows) {
        final thickness = (row['thickness'] as num?)?.toDouble() ?? 0;
        final price = (row['price_per_sqm'] as num?)?.toDouble() ?? 0;
        if (price <= 0 || (thickness - _glassThicknessMm).abs() > 0.01) {
          continue;
        }
        final text = '${row['name'] ?? ''} ${row['type'] ?? ''} '
                '${row['subtype'] ?? ''}'
            .toLowerCase();
        final isTempered = const [
          'trempé',
          'trempe',
          'tempered',
          'securit',
          'sécurit',
          'مقسى',
          'مقسّى',
        ].any(text.contains);
        if (_glassTempered && !isTempered) continue;
        final score = text.contains(_glassType.toLowerCase()) ? 1 : 0;
        if (score > bestScore) {
          best = price;
          bestScore = score;
        }
      }
      return best;
    } catch (error) {
      debugPrint('Tempered glass catalogue price unavailable: $error');
      return null;
    }
  }

  Widget _buildEstimatedPricesWarning({
    required bool glassRateEstimated,
    required bool chantEstimated,
    required bool sablageEstimated,
    required List<String> estimatedAccessories,
  }) {
    final details = <String>[
      if (glassRateEstimated)
        _tr(
          'سعر الزجاج المقسّى لهذه السماكة غير موجود في كتالوج الزجاج',
          'Prix du verre trempé de cette épaisseur absent du catalogue verre',
          'No tempered glass of this thickness in the glass catalogue',
        ),
      if (chantEstimated)
        _tr(
          'سعر شطب الحواف غير موجود في كتالوج الزجاج المقسّى (الخدمات والتشطيب)',
          'Prix du façonnage absent du catalogue verre trempé (Façonnage & Sablage)',
          'Edge finishing price missing from the tempered glass catalogue (Finishing services)',
        ),
      if (sablageEstimated)
        _tr(
          'سعر السفع غير موجود في كتالوج الزجاج المقسّى (الخدمات والتشطيب)',
          'Prix du sablage absent du catalogue verre trempé (Façonnage & Sablage)',
          'Frosting price missing from the tempered glass catalogue (Finishing services)',
        ),
      if (estimatedAccessories.isNotEmpty)
        '${_tr('إكسسوارات غير موجودة في الكتالوج', 'Accessoires absents du catalogue', 'Accessories missing from the catalogue')}: ${estimatedAccessories.join('، ')}',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                    'تقدير غير نهائي: الأسعار المعلّمة بـ * تقديرية',
                    'Estimation non définitive : les prix marqués * sont estimés',
                    'Not final: prices marked * are estimates',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                for (final line in details)
                  Text(
                    '• $line',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade900,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCostAndQuantityDialog() async {
    double totalAreaSqm = 0.0;
    double totalPerimeterM = 0.0;
    for (final panel in _panels) {
      final area = (panel.widthMm / 1000.0) * (panel.heightMm / 1000.0);
      final perim = 2 * (panel.widthMm + panel.heightMm) / 1000.0;
      totalAreaSqm += area;
      totalPerimeterM += perim;
    }

    // Catalogue price first; the built-in rates are only an estimate when
    // the Glass table has no matching tempered glass, and are flagged so.
    final catalogGlassRate = await _catalogTemperedGlassRatePerSqm();
    final glassRateEstimated = catalogGlassRate == null;
    double glassRatePerSqm =
        catalogGlassRate ??
        3500.0 +
            (_glassThicknessMm >= 10
                ? 1000.0
                : (_glassThicknessMm >= 8 ? 500.0 : 0.0));
    if (!mounted) return;
    double? serviceRate(String code) {
      for (final item in _catalogAccessories) {
        if (item['service_code']?.toString() != code) continue;
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        return price > 0 ? price : null;
      }
      return null;
    }

    final catalogChantRate = serviceRate(
      _edgeFinish == 'extra_smooth'
          ? SqlDatabase.temperedGlassEdgeExtraSmoothService
          : SqlDatabase.temperedGlassEdgeSmoothService,
    );
    final catalogSablageRate = serviceRate(
      SqlDatabase.temperedGlassFrostingService,
    );
    final chantRateEstimated = catalogChantRate == null;
    final sablageRateEstimated = catalogSablageRate == null;
    double chantRatePerM =
        catalogChantRate ?? (_edgeFinish == 'extra_smooth' ? 600.0 : 350.0);
    double sablageRatePerSqm = catalogSablageRate ?? 1200.0;
    double laborRatePercent = 15.0;
    double marginPercent = 25.0;

    double sablageAreaSqm = 0.0;
    if (_sablageMode == SablageMode.full) {
      sablageAreaSqm = totalAreaSqm;
    } else if (_sablageMode == SablageMode.decorative &&
        _sablageBands.isNotEmpty) {
      for (final band in _sablageBands) {
        for (final panel in _panels) {
          sablageAreaSqm += (band.widthMm / 1000.0) * (panel.widthMm / 1000.0);
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setCostState) {
          final glassCost = totalAreaSqm * glassRatePerSqm;
          final chantCost = totalPerimeterM * chantRatePerM;
          final sablageCost = sablageAreaSqm * sablageRatePerSqm;

          final List<Map<String, dynamic>> appliedAccessories = [];
          double accessoriesTotal = 0.0;

          if (_showDoorHandle) {
            final handleItem = _catalogAccessories.firstWhere(
              (a) =>
                  a['category'] == 'poignee' &&
                  (a['name']?.toString().contains('30') == true ||
                      a['name']?.toString().contains('porte') == true),
              orElse: () => {
                'name': _tr(
                  'مقبض باب زجاجي ستانلس',
                  'Poignée de porte inox',
                  'Door handle inox',
                ),
                'price': 4500.0,
                'unit': 'piece',
              },
            );
            final price = _colorPrice(handleItem, 4500.0);
            appliedAccessories.add({
              'estimated': handleItem['id'] == null,
              'name':
                  handleItem['name'] ??
                  _tr(
                    'مقبض باب زجاجي ستانلس',
                    'Poignée de porte',
                    'Door handle',
                  ),
              'qty': 1,
              'unit': 'piece',
              'price': price,
              'total': price,
            });
            accessoriesTotal += price;
          }

          if (_showTowelHandle) {
            final towelItem = _catalogAccessories.firstWhere(
              (a) =>
                  a['category'] == 'poignee' &&
                  a['name']?.toString().contains('serviette') == true,
              orElse: () => {
                'name': _tr(
                  'مقبض مناشف كابين دوش',
                  'Porte-serviette douche',
                  'Towel handle',
                ),
                'price': 4800.0,
                'unit': 'piece',
              },
            );
            final price = _colorPrice(towelItem, 4800.0);
            appliedAccessories.add({
              'estimated': towelItem['id'] == null,
              'name':
                  towelItem['name'] ??
                  _tr(
                    'مقبض مناشف كابين دوش',
                    'Porte-serviette douche',
                    'Towel handle',
                  ),
              'qty': 1,
              'unit': 'piece',
              'price': price,
              'total': price,
            });
            accessoriesTotal += price;
          }

          if (_workType == GlassWorkType.slidingShowerCabin) {
            final railItem = _catalogAccessories.firstWhere(
              (a) =>
                  a['category'] == 'profile' &&
                  a['name']?.toString().contains('Rail') == true,
              orElse: () => {
                'name': _tr(
                  'سكة علوية كابين دوش مع رولات',
                  'Rail coulissant douche + roulettes',
                  'Sliding rail + rollers',
                ),
                'price': 16500.0,
                'unit': 'piece',
              },
            );
            final price = _colorPrice(railItem, 16500.0);
            appliedAccessories.add({
              'estimated': railItem['id'] == null,
              'name':
                  railItem['name'] ??
                  _tr(
                    'سكة علوية كابين دوش مع رولات',
                    'Rail coulissant douche',
                    'Sliding rail kit',
                  ),
              'qty': 1,
              'unit': 'piece',
              'price': price,
              'total': price,
            });
            accessoriesTotal += price;
          } else if (_workType == GlassWorkType.showerCabin ||
              _workType == GlassWorkType.singleDoorShowerCabin) {
            final hingeItem = _catalogAccessories.firstWhere(
              (a) => a['category'] == 'charniere',
              orElse: () => {
                'name': _tr(
                  'مفصلة زجاج / جدار 90° ستانلس',
                  'Charnière 90° inox',
                  'Hinge 90° inox',
                ),
                'price': 3800.0,
                'unit': 'piece',
              },
            );
            final price = _colorPrice(hingeItem, 3800.0);
            appliedAccessories.add({
              'estimated': hingeItem['id'] == null,
              'name':
                  hingeItem['name'] ??
                  _tr(
                    'مفصلة زجاج / جدار 90° ستانلس',
                    'Charnière 90° inox',
                    'Hinge 90° inox',
                  ),
              'qty': 2,
              'unit': 'piece',
              'price': price,
              'total': price * 2,
            });
            accessoriesTotal += price * 2;
          } else if (_workType == GlassWorkType.vitrineSingleDoor ||
              _workType == GlassWorkType.vitrineDoubleDoor) {
            final pivotItem = _catalogAccessories.firstWhere(
              (a) => a['name']?.toString().contains('Pivot') == true,
              orElse: () => {
                'name': _tr(
                  'مفصلة أرضية محورية لفاترين',
                  'Pivot de sol vitrine',
                  'Floor spring pivot',
                ),
                'price': 14000.0,
                'unit': 'piece',
              },
            );
            final mult = _workType == GlassWorkType.vitrineDoubleDoor ? 2 : 1;
            final price = _colorPrice(pivotItem, 14000.0);
            appliedAccessories.add({
              'estimated': pivotItem['id'] == null,
              'name':
                  pivotItem['name'] ??
                  _tr(
                    'مفصلة أرضية محورية لفاترين',
                    'Pivot de sol',
                    'Floor pivot',
                  ),
              'qty': mult,
              'unit': 'piece',
              'price': price,
              'total': price * mult,
            });
            accessoriesTotal += price * mult;
          }

          // Automatically suggest / calculate appropriate seals (جوان مغناطيسي 90° أو 180° أو جوان حرف F)
          final is90DegCorner =
              _panels.any((p) => p.isFixed) && _panels.any((p) => p.isDoor);
          if (_workType == GlassWorkType.showerCabin ||
              _workType == GlassWorkType.slidingShowerCabin) {
            // Check if user hasn't explicitly picked a joint yet
            final hasExplicitJoint = _selectedAccessories.keys.any((id) {
              final a = _catalogAccessories.firstWhere(
                (x) => x['id'] == id,
                orElse: () => <String, dynamic>{},
              );
              return a['category'] == 'joint';
            });

            if (!hasExplicitJoint && _gasketItems.values.every((id) => id <= 0)) {
              // 1. Magnetic joint for 90° corner or straight 180°
              final jointNameKeyword = is90DegCorner ? '90°' : '180°';
              final magnetJointItem = _catalogAccessories.firstWhere(
                (a) =>
                    a['category'] == 'joint' &&
                    a['name']?.toString().contains('مغناطيسي') == true &&
                    a['name']?.toString().contains(jointNameKeyword) == true,
                orElse: () => _catalogAccessories.firstWhere(
                  (a) =>
                      a['category'] == 'joint' &&
                      a['name']?.toString().contains('مغناطيسي') == true,
                  orElse: () => <String, dynamic>{
                    'name': is90DegCorner
                        ? 'جوان مغناطيسي 90° (Joint magnétique 90°)'
                        : 'جوان مغناطيسي 180° (Joint magnétique 180°)',
                    'price': is90DegCorner ? 2100.0 : 1900.0,
                    'unit': 'piece',
                  },
                ),
              );
              final jPrice =
                  _colorPrice(magnetJointItem, 2000.0);
              appliedAccessories.add({
                'estimated': magnetJointItem['id'] == null,
                'name':
                    magnetJointItem['name'] ??
                    (is90DegCorner
                        ? 'جوان مغناطيسي 90°'
                        : 'جوان مغناطيسي 180°'),
                'qty': 1,
                'unit': 'piece',
                'price': jPrice,
                'total': jPrice,
              });
              accessoriesTotal += jPrice;

              // 2. Joint profil F for side water sealing
              final fJointItem = _catalogAccessories.firstWhere(
                (a) =>
                    a['category'] == 'joint' &&
                    (a['name']?.toString().contains('حرف F') == true ||
                        a['name']?.toString().contains('profil F') == true),
                orElse: () => <String, dynamic>{
                  'name': 'جوان حرف F مانع تسرب الماء (Joint profil F)',
                  'price': 1600.0,
                  'unit': 'piece',
                },
              );
              final fPrice =
                  _colorPrice(fJointItem, 1600.0);
              appliedAccessories.add({
                'estimated': fJointItem['id'] == null,
                'name': fJointItem['name'] ?? 'جوان حرف F مانع تسرب الماء',
                'qty': 1,
                'unit': 'piece',
                'price': fPrice,
                'total': fPrice,
              });
              accessoriesTotal += fPrice;
            }
          }

          for (final line in _profileAndGasketCostLines()) {
            appliedAccessories.add(line);
            accessoriesTotal += (line['total'] as num).toDouble();
          }

          for (final entry in _selectedAccessories.entries) {
            final item = _catalogAccessories.firstWhere(
              (a) => a['id'] == entry.key,
              orElse: () => <String, dynamic>{},
            );
            if (item.isNotEmpty && entry.value > 0) {
              final price = _colorPrice(item, 0.0);
              final tot = price * entry.value;
              appliedAccessories.add({
                'estimated': item['id'] == null,
                'name': item['name'] ?? '',
                'qty': entry.value,
                'unit': item['unit'] ?? 'piece',
                'price': price,
                'total': tot,
              });
              accessoriesTotal += tot;
            }
          }

          final estimatedAccessories = appliedAccessories
              .where((acc) => acc['estimated'] == true)
              .map((acc) => acc['name'].toString())
              .toList();
          final chantEstimated = chantRateEstimated && totalPerimeterM > 0;
          final sablageEstimated = sablageRateEstimated && sablageAreaSqm > 0;
          final hasEstimatedPrices =
              glassRateEstimated ||
              chantEstimated ||
              sablageEstimated ||
              estimatedAccessories.isNotEmpty;
          final totalMaterialsCost =
              glassCost + chantCost + sablageCost + accessoriesTotal;
          final laborAmount = totalMaterialsCost * (laborRatePercent / 100.0);
          final subtotalCost = totalMaterialsCost + laborAmount;
          final marginAmount = subtotalCost * (marginPercent / 100.0);
          final finalSellingPrice = subtotalCost + marginAmount;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.calculate_outlined,
                    color: Colors.amber.shade900,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _tr(
                      'جدول الكميات والتكلفة للزجاج المقسّى',
                      'Tableau des Quantités et Coûts (Verre Trempé)',
                      'Tempered Glass Quantities & Cost',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 720,
              height: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasEstimatedPrices)
                      _buildEstimatedPricesWarning(
                        glassRateEstimated: glassRateEstimated,
                        chantEstimated: chantEstimated,
                        sablageEstimated: sablageEstimated,
                        estimatedAccessories: estimatedAccessories,
                      ),
                    _buildCostSectionHeader(
                      _tr(
                        '1. تفاصيل ألواح الزجاج',
                        '1. Détail des panneaux de verre',
                        '1. Glass Panels Detail',
                      ),
                      Icons.window,
                    ),
                    Table(
                      border: TableBorder.all(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      columnWidths: const {
                        0: FlexColumnWidth(2.5),
                        1: FlexColumnWidth(2.2),
                        2: FlexColumnWidth(1.8),
                        3: FlexColumnWidth(2),
                        4: FlexColumnWidth(2),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.cyan.shade50),
                          children: [
                            _tableHeaderCell(_tr('اللوح', 'Panneau', 'Panel')),
                            _tableHeaderCell(
                              _tr('الأبعاد (مم)', 'Dim. (mm)', 'Dim (mm)'),
                            ),
                            _tableHeaderCell(_tr('المساحة', 'Surface', 'Area')),
                            _tableHeaderCell(
                              _tr('سعر م²', 'Prix/m²', 'Rate/m²'),
                            ),
                            _tableHeaderCell(_tr('المجموع', 'Total', 'Total')),
                          ],
                        ),
                        ..._panels.asMap().entries.map((entry) {
                          final p = entry.value;
                          final role = p.isDoor
                              ? _tr('باب', 'Porte', 'Door')
                              : _tr('ثابت', 'Fixe', 'Fixed');
                          final a =
                              (p.widthMm / 1000.0) * (p.heightMm / 1000.0);
                          final tot = a * glassRatePerSqm;
                          return TableRow(
                            children: [
                              _tableCell(
                                '$role #${entry.key + 1} ($_glassType - ${_glassThicknessMm.toStringAsFixed(0)}mm)',
                              ),
                              _tableCell(
                                '${p.widthMm.toStringAsFixed(0)} × ${p.heightMm.toStringAsFixed(0)}',
                              ),
                              _tableCell('${a.toStringAsFixed(2)} m²'),
                              _tableCell(
                                '${glassRatePerSqm.toStringAsFixed(0)} DZD${glassRateEstimated ? ' *' : ''}',
                              ),
                              _tableCell(
                                '${tot.toStringAsFixed(0)} DZD',
                                bold: true,
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),

                    _buildCostSectionHeader(
                      _tr(
                        '2. المعالجة السطحية والحواف',
                        '2. Façonnage et Sablage',
                        '2. Edge Finishing & Frosting',
                      ),
                      Icons.architecture,
                    ),
                    Table(
                      border: TableBorder.all(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.cyan.shade50),
                          children: [
                            _tableHeaderCell(
                              _tr('نوع المعالجة', 'Traitement', 'Treatment'),
                            ),
                            _tableHeaderCell(
                              _tr('الكمية', 'Quantité', 'Quantity'),
                            ),
                            _tableHeaderCell(
                              _tr('سعر الوحدة', 'Prix unitaire', 'Unit rate'),
                            ),
                            _tableHeaderCell(_tr('المجموع', 'Total', 'Total')),
                          ],
                        ),
                        TableRow(
                          children: [
                            _tableCell(
                              '${_tr('شطب الحواف', 'Façonnage chants', 'Edge finish')} (${_edgeFinishLabel(_edgeFinish)})',
                            ),
                            _tableCell(
                              '${totalPerimeterM.toStringAsFixed(2)} m',
                            ),
                            _tableCell(
                              '${chantRatePerM.toStringAsFixed(0)} DZD/m${chantEstimated ? ' *' : ''}',
                            ),
                            _tableCell(
                              '${chantCost.toStringAsFixed(0)} DZD',
                              bold: true,
                            ),
                          ],
                        ),
                        if (sablageAreaSqm > 0)
                          TableRow(
                            children: [
                              _tableCell(
                                '${_tr('الصابلاج', 'Sablage', 'Frosting')} (${_sablageMode.name})',
                              ),
                              _tableCell(
                                '${sablageAreaSqm.toStringAsFixed(2)} m²',
                              ),
                              _tableCell(
                                '${sablageRatePerSqm.toStringAsFixed(0)} DZD/m²${sablageEstimated ? ' *' : ''}',
                              ),
                              _tableCell(
                                '${sablageCost.toStringAsFixed(0)} DZD',
                                bold: true,
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    _buildCostSectionHeader(
                      _tr(
                        '3. الإكسسوارات والقطاعات المرفقة',
                        '3. Accessoires et Profilés',
                        '3. Hardware & Accessories',
                      ),
                      Icons.extension,
                    ),
                    if (appliedAccessories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          _tr(
                            'لا توجد إكسسوارات مضافة.',
                            'Aucun accessoire.',
                            'No accessories.',
                          ),
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    else
                      Table(
                        border: TableBorder.all(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: Colors.cyan.shade50,
                            ),
                            children: [
                              _tableHeaderCell(
                                _tr('العنصر / الإكسسوار', 'Accessoire', 'Item'),
                              ),
                              _tableHeaderCell(
                                _tr('الكمية', 'Quantité', 'Qty'),
                              ),
                              _tableHeaderCell(
                                _tr('سعر القطعة', 'Prix unit.', 'Unit Price'),
                              ),
                              _tableHeaderCell(
                                _tr('الإجمالي', 'Total', 'Total'),
                              ),
                            ],
                          ),
                          ...appliedAccessories.map(
                            (acc) => TableRow(
                              children: [
                                _tableCell(acc['name'].toString()),
                                _tableCell(
                                  '${acc['qty']} ${acc['unit'] == 'meter' ? 'm' : 'pce'}',
                                ),
                                _tableCell(
                                  '${(acc['price'] as double).toStringAsFixed(0)} DZD${acc['estimated'] == true ? ' *' : ''}',
                                ),
                                _tableCell(
                                  '${(acc['total'] as double).toStringAsFixed(0)} DZD',
                                  bold: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _tr(
                                  'إجمالي تكلفة المواد:',
                                  'Coût total matériaux:',
                                  'Total materials cost:',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${totalMaterialsCost.toStringAsFixed(0)} DZD',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_tr('المصنعية والتركيب', 'Main d\'œuvre & Pose', 'Labor & Installation')} (${laborRatePercent.toStringAsFixed(0)}%):',
                              ),
                              Text(
                                '${laborAmount.toStringAsFixed(0)} DZD',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_tr('هامش الربح', 'Marge bénéficiaire', 'Profit Margin')} (${marginPercent.toStringAsFixed(0)}%):',
                              ),
                              Text(
                                '${marginAmount.toStringAsFixed(0)} DZD',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const Divider(thickness: 1.5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _tr(
                                  'سعر البيع المقترح الإجمالي:',
                                  'Prix de vente total suggéré:',
                                  'Suggested Total Selling Price:',
                                ),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.cyan.shade900,
                                ),
                              ),
                              Text(
                                '${finalSellingPrice.toStringAsFixed(0)} DZD',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(_tr('إغلاق', 'Fermer', 'Close')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEdgeFinishSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.rounded_corner),
              title: Text(_edgeFinishLabel('smooth')),
              trailing: _edgeFinish == 'smooth'
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(sheetContext, 'smooth'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(_edgeFinishLabel('extra_smooth')),
              trailing: _edgeFinish == 'extra_smooth'
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(sheetContext, 'extra_smooth'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted && selected != _edgeFinish) {
      setState(() => _edgeFinish = selected);
    }
  }

  Map<String, dynamic>? _catalogItem(int? id) {
    if (id == null || id <= 0) return null;
    return _catalogAccessories.where((a) => a['id'] == id).firstOrNull;
  }

  bool _itemFitsThickness(Map<String, dynamic> item) =>
      GlassAccessoryTemplate.fromItem(item).fitsThickness(_glassThicknessMm);

  /// Profile used for [role]: the user's choice, else the first catalogue
  /// profile of that role made for the glass thickness.
  Map<String, dynamic>? _profileItemFor(String role) {
    final chosen = _profileItems[role];
    if (chosen != null) return _catalogItem(chosen);
    return _catalogAccessories
        .where(
          (a) =>
              a['category'] == 'profile' &&
              a['profile_role'] == role &&
              _itemFitsThickness(a),
        )
        .firstOrNull;
  }

  /// Profile lengths of the current sliding layout, or null for another
  /// layout.
  SlidingGlassProfiles? get _slidingProfiles {
    if (!_isSlidingStraight) return null;
    final door = _panels.where((p) => p.isDoor).firstOrNull;
    final fixed = _panels.where((p) => p.isFixed).firstOrNull;
    if (door == null || fixed == null) return null;
    return SlidingGlassProfiles(
      fixedWidthMm: fixed.widthMm,
      fixedHeightMm: fixed.heightMm,
      overallWidthMm: _overallWidthMm,
    );
  }

  String _gasketTypeLabel(String type) => switch (type) {
    GlassGasketType.magnetic90 => _tr('مغناطيسي 90°', 'Magnétique 90°', 'Magnetic 90°'),
    GlassGasketType.magnetic180 => _tr('مغناطيسي 180°', 'Magnétique 180°', 'Magnetic 180°'),
    GlassGasketType.h => _tr('جوان H', 'Joint H', 'H gasket'),
    GlassGasketType.f => _tr('جوان F', 'Joint F', 'F gasket'),
    GlassGasketType.bulb => _tr('جوان بومبي', 'Joint bombé', 'Bulb gasket'),
    GlassGasketType.rail => _tr('جوان البروفيل', 'Joint de profilé', 'Profile gasket'),
    _ => '',
  };

  /// Rows the cost table adds for the chosen profiles and gaskets. Profiles
  /// and the profile gasket are counted by the metre, the door gaskets by
  /// the piece (one per door).
  List<Map<String, dynamic>> _profileAndGasketCostLines() {
    final lines = <Map<String, dynamic>>[];
    void add(Map<String, dynamic>? item, double qty, String unit) {
      if (item == null || qty <= 0) return;
      final price = _colorPrice(item, 0.0);
      final rounded = double.parse(qty.toStringAsFixed(2));
      lines.add({
        'estimated': false,
        'name': item['name'] ?? '',
        'qty': unit == 'meter' ? rounded : rounded.round(),
        'unit': unit,
        'price': price,
        'total': price * rounded,
      });
    }

    final profiles = _slidingProfiles;
    if (profiles != null && _showProfiles) {
      add(
        _profileItemFor(GlassProfileRole.uChannel),
        profiles.uChannelMm / 1000,
        'meter',
      );
      add(
        _profileItemFor(GlassProfileRole.topRail),
        profiles.topRailMm / 1000,
        'meter',
      );
    }
    final doorCount = _panels.where((p) => p.isDoor).length;
    for (final location in [
      GlassGasketLocation.doorWall,
      GlassGasketLocation.doorFixed,
    ]) {
      add(_catalogItem(_gasketItems[location]), doorCount.toDouble(), 'piece');
    }
    if (profiles != null) {
      add(
        _catalogItem(_gasketItems[GlassGasketLocation.profile]),
        profiles.profileGasketMm / 1000,
        'meter',
      );
    }
    return lines;
  }

  Future<void> _showProfilesAndGasketsDialog() async {
    final joints = _catalogAccessories
        .where((a) => a['category'] == 'joint')
        .toList();
    final profilesCatalog = _catalogAccessories
        .where((a) => a['category'] == 'profile')
        .toList();

    String itemLabel(Map<String, dynamic> item) {
      final type = _gasketTypeLabel(item['joint_type']?.toString() ?? '');
      final name = item['name']?.toString() ?? '';
      return type.isEmpty ? name : '$name · $type';
    }

    Widget picker({
      required String label,
      required List<Map<String, dynamic>> items,
      required int? value,
      required ValueChanged<int?> onChanged,
    }) {
      final ids = items.map((i) => i['id'] as int).toSet();
      return DropdownButtonFormField<int>(
        value: value != null && (value == 0 || ids.contains(value))
            ? value
            : 0,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          DropdownMenuItem(value: 0, child: Text(_tr('بدون', 'Aucun', 'None'))),
          ...items.map(
            (item) => DropdownMenuItem(
              value: item['id'] as int,
              child: Text(itemLabel(item), overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: onChanged,
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void update(VoidCallback change) {
            _pushHistory();
            setState(change);
            setDialogState(() {});
          }

          final sliding = _slidingProfiles != null;
          return AlertDialog(
            title: Text(
              _tr('البروفيلات والجوانات', 'Profilés & joints', 'Profiles & gaskets'),
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _hardwareColors.contains(_hardwareColor)
                          ? _hardwareColor
                          : '',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _tr(
                          'لون الإكسسوارات',
                          'Couleur de la quincaillerie',
                          'Hardware colour',
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_tr('السعر الأساسي', 'Prix de base', 'Base price')),
                        ),
                        ..._hardwareColors.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                      ],
                      onChanged: (v) => update(() => _hardwareColor = v ?? ''),
                    ),
                    const SizedBox(height: 14),
                    if (sliding) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showProfiles,
                        title: Text(
                          _tr(
                            'بروفيل U للثابت والراي العلوي',
                            'Profilé U du fixe et rail supérieur',
                            'Fixed U channel and top rail',
                          ),
                        ),
                        subtitle: Text(
                          _tr(
                            'U تحت الثابت ومن جهة الحائط، والثابت يدخل الراي 15 مم.',
                            'U sous le fixe et côté mur ; le fixe entre de 15 mm dans le rail.',
                            'U under the fixed glass and on the wall side; the fixed glass enters the rail by 15 mm.',
                          ),
                          style: const TextStyle(fontSize: 11),
                        ),
                        onChanged: (v) => update(() => _showProfiles = v),
                      ),
                      if (_showProfiles) ...[
                        picker(
                          label: _tr('بروفيل U (باغيت)', 'Profilé U (baguette)', 'U channel'),
                          items: profilesCatalog
                              .where((a) => a['profile_role'] != GlassProfileRole.topRail)
                              .toList(),
                          value: _profileItemFor(GlassProfileRole.uChannel)?['id'] as int? ??
                              _profileItems[GlassProfileRole.uChannel],
                          onChanged: (v) => update(
                            () => _profileItems[GlassProfileRole.uChannel] = v ?? 0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        picker(
                          label: _tr('الراي العلوي', 'Rail supérieur', 'Top rail'),
                          items: profilesCatalog
                              .where((a) => a['profile_role'] != GlassProfileRole.uChannel)
                              .toList(),
                          value: _profileItemFor(GlassProfileRole.topRail)?['id'] as int? ??
                              _profileItems[GlassProfileRole.topRail],
                          onChanged: (v) => update(
                            () => _profileItems[GlassProfileRole.topRail] = v ?? 0,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                    picker(
                      label: _tr(
                        'جوان حافة الباب من جهة الحائط (بالقطعة)',
                        'Joint du chant de porte côté mur (pièce)',
                        'Door edge gasket, wall side (piece)',
                      ),
                      items: joints
                          .where((a) => a['joint_type'] != GlassGasketType.rail)
                          .toList(),
                      value: _gasketItems[GlassGasketLocation.doorWall],
                      onChanged: (v) => update(
                        () => _gasketItems[GlassGasketLocation.doorWall] = v ?? 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    picker(
                      label: _tr(
                        'جوان بين الثابت والباب (بالقطعة)',
                        'Joint entre fixe et porte (pièce)',
                        'Gasket between fixed and door (piece)',
                      ),
                      items: joints
                          .where((a) => a['joint_type'] != GlassGasketType.rail)
                          .toList(),
                      value: _gasketItems[GlassGasketLocation.doorFixed],
                      onChanged: (v) => update(
                        () => _gasketItems[GlassGasketLocation.doorFixed] = v ?? 0,
                      ),
                    ),
                    if (sliding) ...[
                      const SizedBox(height: 10),
                      picker(
                        label: _tr(
                          'جوان بين البروفيل والزجاج (بالمتر)',
                          'Joint entre profilé et verre (au mètre)',
                          'Gasket between profile and glass (per metre)',
                        ),
                        items: joints
                            .where((a) =>
                                (a['joint_type']?.toString() ?? '').isEmpty ||
                                a['joint_type'] == GlassGasketType.rail)
                            .toList(),
                        value: _gasketItems[GlassGasketLocation.profile],
                        onChanged: (v) => update(
                          () => _gasketItems[GlassGasketLocation.profile] = v ?? 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_tr('إغلاق', 'Fermer', 'Close')),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Drills the holes of a catalogue accessory in a panel it can be mounted
  /// on, from the position of its first hole.
  Future<void> _placeAccessoryOnGlass(Map<String, dynamic> item) async {
    if (_refuseWhenKitLocked()) return;
    final template = GlassAccessoryTemplate.fromItem(item);
    if (template.holeCount == 0 || _panels.isEmpty) return;
    final eligible = [
      for (var i = 0; i < _panels.length; i++)
        if (GlassMountTarget.fitsPanel(
          template.mountTarget,
          _panels[i].isDoor ? 'door' : 'fixed',
        ))
          i,
    ];
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'لا يوجد لوح يناسب مكان تركيب هذا الإكسسوار.',
              'Aucun panneau ne convient au montage de cet accessoire.',
              'No panel matches where this accessory is mounted.',
            ),
          ),
        ),
      );
      return;
    }
    var panelIndex =
        eligible.contains(_selectedPanelIndex) ? _selectedPanelIndex! : eligible.first;
    var vertical = template.vertical;
    GlassAccessoryTemplate oriented() => GlassAccessoryTemplate(
      holeDiameters: template.holeDiameters,
      holeSpacings: template.holeSpacings,
      vertical: vertical,
    );
    double defaultX(_GlassPanel panel) => vertical
        ? panel.widthMm / 2
        : (panel.widthMm - template.spanMm) / 2;
    double defaultY(_GlassPanel panel) => vertical
        ? (panel.heightMm - template.spanMm) / 2
        : panel.heightMm / 2;
    final xController = TextEditingController(
      text: defaultX(_panels[panelIndex]).toStringAsFixed(0),
    );
    final yController = TextEditingController(
      text: defaultY(_panels[panelIndex]).toStringAsFixed(0),
    );
    String? error;
    final placed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final x = _parseMillimeters(xController.text);
            final y = _parseMillimeters(yController.text);
            final panel = _panels[panelIndex];
            if (x == null ||
                y == null ||
                !oriented().fitsGlass(
                  widthMm: panel.widthMm,
                  heightMm: panel.heightMm,
                  xMm: x,
                  yMm: y,
                )) {
              setDialogState(
                () => error = _tr(
                  'يجب أن تبقى كل الثقوب داخل الزجاج.',
                  'Tous les trous doivent rester dans le verre.',
                  'Every hole must stay inside the glass.',
                ),
              );
              return;
            }
            Navigator.pop(dialogContext, true);
          }

          final spacings = template.holeSpacings
              .map((v) => v.toStringAsFixed(0))
              .join(' / ');
          final diameters = template.holeDiameters
              .map((v) => 'Ø${v.toStringAsFixed(0)}')
              .join(' ');
          return AlertDialog(
            title: Text(item['name']?.toString() ?? ''),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${template.holeCount} ${_tr('ثقوب', 'trous', 'holes')}: $diameters'
                    '${spacings.isEmpty ? '' : '  ·  ${_tr('المسافات', 'entraxes', 'spacings')}: $spacings mm'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (!template.fitsThickness(_glassThicknessMm))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _tr(
                          'تنبيه: هذا الإكسسوار مصنوع لزجاج ${template.glassThicknessMm.toStringAsFixed(0)} مم.',
                          'Attention : accessoire prévu pour un verre de ${template.glassThicknessMm.toStringAsFixed(0)} mm.',
                          'Warning: this accessory is made for ${template.glassThicknessMm.toStringAsFixed(0)} mm glass.',
                        ),
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: panelIndex,
                    decoration: InputDecoration(
                      labelText: _tr('اللوح', 'Panneau', 'Panel'),
                      border: const OutlineInputBorder(),
                    ),
                    items: eligible
                        .map(
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${_panels[i].isDoor ? _tr('باب', 'Porte', 'Door') : _tr('ثابت', 'Fixe', 'Fixed')} #${i + 1}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() {
                      panelIndex = v ?? panelIndex;
                      xController.text = defaultX(_panels[panelIndex]).toStringAsFixed(0);
                      yController.text = defaultY(_panels[panelIndex]).toStringAsFixed(0);
                    }),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(_tr('أفقي', 'Horizontal', 'Horizontal'))),
                      ButtonSegment(value: true, label: Text(_tr('عمودي', 'Vertical', 'Vertical'))),
                    ],
                    selected: {vertical},
                    onSelectionChanged: (v) => setDialogState(() {
                      vertical = v.first;
                      xController.text = defaultX(_panels[panelIndex]).toStringAsFixed(0);
                      yController.text = defaultY(_panels[panelIndex]).toStringAsFixed(0);
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: xController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _tr(
                        'مركز الثقب الأول عن اليسار (X)',
                        'Centre du 1er trou depuis la gauche (X)',
                        'First hole centre from left (X)',
                      ),
                      suffixText: 'mm',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: yController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: _tr(
                        'مركز الثقب الأول عن الأعلى (Y)',
                        'Centre du 1er trou depuis le haut (Y)',
                        'First hole centre from top (Y)',
                      ),
                      suffixText: 'mm',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_tr('إلغاء', 'Annuler', 'Cancel')),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(_tr('وضع على الزجاج', 'Placer sur le verre', 'Place on glass')),
              ),
            ],
          );
        },
      ),
    );
    if (placed != true || !mounted) return;
    final x = _parseMillimeters(xController.text)!;
    final y = _parseMillimeters(yController.text)!;
    final itemId = item['id'] as int;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final holes = oriented().holes();
    _pushHistory();
    setState(() {
      final panel = _panels[panelIndex];
      for (var i = 0; i < holes.length; i++) {
        panel.holes.add(
          _GlassHole(
            xMm: x + holes[i].dxMm,
            yMm: y + holes[i].dyMm,
            diameterMm: holes[i].diameterMm,
            purpose: 'acc_${itemId}_${stamp}_$i',
          ),
        );
      }
      _selectedPanelIndex = panelIndex;
      _selectedAccessories[itemId] = (_selectedAccessories[itemId] ?? 0) + 1;
    });
  }

  Future<void> _showMobileToolsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        void open(Future<void> Function() action) {
          Navigator.pop(sheetContext);
          Future.microtask(() {
            if (mounted) action();
          });
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.pan_tool_outlined),
                title: Text(_tr('المقبض', 'Poignée', 'Handle')),
                onTap: () => open(_editHandleFromToolbar),
              ),
              ListTile(
                leading: const Icon(Icons.brush_outlined),
                title: Text(_tr('الصبلاج', 'Sablage', 'Frosting')),
                onTap: () => open(_showSablageSheet),
              ),
              ListTile(
                leading: const Icon(Icons.content_cut),
                title: Text(
                  _tr(
                    'خيارات نظام الزجاج',
                    'Système de vitrage',
                    'Glass system',
                  ),
                ),
                onTap: () => open(_showWorkTypeSheet),
              ),
              ListTile(
                leading: const Icon(Icons.rounded_corner),
                title: Text(_tr('نوع الحواف', 'Type de chants', 'Edge type')),
                onTap: () => open(_showEdgeFinishSheet),
              ),
              ListTile(
                leading: const Icon(Icons.view_column_outlined),
                title: Text(
                  _tr('البروفيلات والجوانات', 'Profilés & joints', 'Profiles & gaskets'),
                ),
                onTap: () => open(_showProfilesAndGasketsDialog),
              ),
            ],
          ),
        );
      },
    );
  }

  InputDecoration _toolbarFieldDecoration(String label, {String? suffixText}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffixText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(
        fontSize: 10,
        color: Colors.blueGrey.shade600,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(10, 15, 8, 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.blueGrey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.blueGrey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.cyan.shade700, width: 1.5),
      ),
    );
  }

  Widget _buildToolbarDropdownField({
    required String label,
    required String value,
    required VoidCallback onTap,
    IconData? icon,
    double? width,
    double height = 38,
    bool showDropdownArrow = true,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          splashColor: Colors.cyan.withValues(alpha: 0.10),
          highlightColor: Colors.cyan.withValues(alpha: 0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.blueGrey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1,
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 15, color: Colors.cyan.shade800),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.1,
                          color: Color(0xFF263238),
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (showDropdownArrow)
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.blueGrey.shade600,
                        size: 16,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawingToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E2E8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ROW 1: Dimensions, Systems, Door, and Controls
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToolbarDropdownField(
                  label: _tr('الأبعاد', 'Dimensions', 'Dimensions'),
                  value: _measurementSummary(),
                  icon: Icons.straighten,
                  width: 165,
                  showDropdownArrow: false,
                  onTap: _editMeasurements,
                ),
                if (_isSlidingStraight) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 95,
                    height: 38,
                    child: TextField(
                      controller: _doorWidthController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) {
                        _doorWidthCustomized = true;
                        if (_overallDrawingRect != null) {
                          setState(_applySlidingLayout);
                        }
                      },
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _toolbarFieldDecoration(
                        _tr('عرض الباب', 'Larg. porte', 'Door width'),
                        suffixText: 'mm',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.blueGrey.shade200),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: _tr(
                        'قلب الباب',
                        'Inverser la porte',
                        'Swap door',
                      ),
                      onPressed: _toggleSlidingSides,
                      icon: const Icon(
                        Icons.swap_horiz,
                        color: Colors.black87,
                        size: 20,
                      ),
                    ),
                  ),
                ],
                if (!_isSlidingStraight && _panels.length >= 2) ...[
                  const SizedBox(width: 4),
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.blueGrey.shade200),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: _tr(
                        'قلب ترتيب الألواح',
                        'Inverser les panneaux',
                        'Swap panels',
                      ),
                      onPressed: _swapPanelsOrder,
                      icon: const Icon(
                        Icons.swap_horiz_rounded,
                        color: Colors.cyan,
                        size: 20,
                      ),
                    ),
                  ),
                ],
                if (_panels.any((p) => p.isDoor)) ...[
                  const SizedBox(width: 4),
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.blueGrey.shade200),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: _tr(
                        'تغيير جهة المفصلات (حائط ⇄ زجاج)',
                        'Changer côté charnières',
                        'Toggle hinge side',
                      ),
                      onPressed: _toggleHingeSide,
                      icon: const Icon(
                        Icons.flip_to_back_rounded,
                        color: Colors.deepOrange,
                        size: 20,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Builder(
                  builder: (btnCtx) => _buildToolbarDropdownField(
                    label: _tr(
                      'خيارات النظام',
                      'Options système',
                      'System options',
                    ),
                    value: _currentSystemName,
                    icon: Icons.dashboard_customize_outlined,
                    width: 160,
                    onTap: () => _showWorkTypeMenu(btnCtx),
                  ),
                ),
                const SizedBox(width: 6),
                _buildToolbarDropdownField(
                  label: _tr('أنظمة جاهزة', 'Systèmes prêts', 'Preset Systems'),
                  value: _tr('معاينة بصرية', 'Aperçu visuel', 'Visual preview'),
                  icon: Icons.auto_awesome_mosaic_rounded,
                  width: 140,
                  showDropdownArrow: false,
                  onTap: _showPresetSystemsGallery,
                ),
                const SizedBox(width: 6),
                _buildToolbarDropdownField(
                  label: _tr('كيت الزجاج', 'Kit verre', 'Glass Kit'),
                  value:
                      _selectedKit?['name']?.toString() ??
                      _tr('اختيار كيت', 'Choisir kit', 'Select kit'),
                  icon: Icons.architecture_outlined,
                  width: 140,
                  onTap: _showKitSelectionDialog,
                ),
                const SizedBox(width: 8),
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.blueGrey.shade200),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 38,
                        ),
                        tooltip: _tr('تصغير', 'Zoom arrière', 'Zoom out'),
                        onPressed: () => _changeZoom(-0.1),
                        icon: const Icon(
                          Icons.zoom_out,
                          size: 16,
                          color: Colors.black87,
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _zoom = 1.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '${(_zoom * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 38,
                        ),
                        tooltip: _tr('تكبير', 'Zoom avant', 'Zoom in'),
                        onPressed: () => _changeZoom(0.1),
                        icon: const Icon(
                          Icons.zoom_in,
                          size: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // ROW 2: Glass Specs, Finishing, Holes, Handles, Sablage & Accessories
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 95,
                  height: 38,
                  child: DropdownButtonFormField<double>(
                    value: _glassThicknessMm,
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.black87,
                      size: 18,
                    ),
                    decoration: _toolbarFieldDecoration(
                      _tr('السمك', 'Épaisseur', 'Thickness'),
                    ),
                    items: const [10.0, 8.0, 6.0, 5.0, 4.0]
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text('${t.toStringAsFixed(0)} mm'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val == null || val == _glassThicknessMm) return;
                      _pushHistory();
                      setState(() => _glassThicknessMm = val);
                      _loadSystemRules();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 110,
                  height: 38,
                  child: DropdownButtonFormField<String>(
                    value: _glassType,
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.black87,
                      size: 18,
                    ),
                    decoration: _toolbarFieldDecoration(
                      _tr('نوع الزجاج', 'Type', 'Type'),
                    ),
                    items: const [
                      'شفاف',
                      'شفاف إضافي',
                      'ملون',
                      'عاكس',
                      'مصفح',
                      'معتّم',
                      'ساتان',
                      'مطبوع',
                    ]
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              _glassTypeLabel(t),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val == null || val == _glassType) return;
                      setState(() => _glassType = val);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                _buildToolbarDropdownField(
                  label: _tr('التقسية', 'Trempe', 'Tempering'),
                  value: _glassTempered
                      ? _tr('مقسّى', 'Trempé', 'Tempered')
                      : _tr('عادي', 'Normal', 'Standard'),
                  icon: Icons.shield_outlined,
                  width: 95,
                  showDropdownArrow: false,
                  onTap: () => setState(() => _glassTempered = !_glassTempered),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 120,
                  height: 38,
                  child: DropdownButtonFormField<String>(
                    value: _edgeFinish,
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.black87,
                      size: 18,
                    ),
                    decoration: _toolbarFieldDecoration(
                      _tr('الحواف', 'Chants', 'Edges'),
                    ),
                    items: const ['smooth', 'extra_smooth']
                        .map(
                          (f) => DropdownMenuItem(
                            value: f,
                            child: Text(
                              _edgeFinishLabel(f),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val == null || val == _edgeFinish) return;
                      setState(() => _edgeFinish = val);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 120,
                  height: 38,
                  child: DropdownButtonFormField<_HoleDimensionMode>(
                    value: _holeDimensionMode,
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.black87,
                      size: 18,
                    ),
                    decoration: _toolbarFieldDecoration(
                      _tr('أبعاد الثقوب', 'Cotation', 'Hole dims'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: _HoleDimensionMode.edge,
                        child: Text(_tr('حافة الثقب', 'Bord', 'Edge')),
                      ),
                      DropdownMenuItem(
                        value: _HoleDimensionMode.center,
                        child: Text(_tr('مركز الثقب', 'Centre', 'Center')),
                      ),
                    ],
                    onChanged: (m) {
                      if (m != null && m != _holeDimensionMode) {
                        setState(() => _holeDimensionMode = m);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                _buildToolbarDropdownField(
                  label: _tr('المقابض', 'Poignées', 'Handles'),
                  value: _handlesButtonLabel(),
                  icon: Icons.pan_tool_outlined,
                  width: 125,
                  onTap: _showDatabaseHandlesPicker,
                ),
                const SizedBox(width: 6),
                Builder(
                  builder: (btnCtx) => _buildToolbarDropdownField(
                    label: _tr('الصابلاج', 'Sablage', 'Frosting'),
                    value: switch (_sablageMode) {
                      _SablageMode.full => _tr('كامل', 'Complet', 'Full'),
                      _SablageMode.decorative => _tr(
                        'ديكور',
                        'Décoratif',
                        'Decorative',
                      ),
                      _SablageMode.none => _tr('بدون', 'Sans', 'None'),
                    },
                    icon: Icons.brush_outlined,
                    width: 110,
                    onTap: () => _showSablageMenu(btnCtx),
                  ),
                ),
                const SizedBox(width: 6),
                Builder(
                  builder: (btnCtx) {
                    final totalAcc = _selectedAccessories.values.fold(
                      0,
                      (a, b) => a + b,
                    );
                    return _buildToolbarDropdownField(
                      label: _tr('الإكسسوارات', 'Accessoires', 'Accessories'),
                      value: totalAcc == 0
                          ? _tr('اختيار', 'Choisir', 'Select')
                          : '$totalAcc ${_tr('عنصر', 'élém.', 'items')}',
                      icon: Icons.hardware_outlined,
                      width: 125,
                      onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = _isCompactLayout(context);

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildAccessoriesEndDrawer(context),
      appBar: AppBar(
        title: Text(_tr('زجاج مقسّى', 'Verre trempé', 'Tempered glass')),
        backgroundColor: Colors.cyan.shade800,
        foregroundColor: Colors.white,
        actions: [
          SizedBox(
            width: compact
                ? (MediaQuery.sizeOf(context).width * 0.58).clamp(170.0, 300.0)
                : (MediaQuery.sizeOf(context).width * 0.72).clamp(420.0, 760.0),
            child: ExplicitScrollbar(
              controller: _appBarActionsScrollController,
              thumbVisibility: compact,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                controller: _appBarActionsScrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
            tooltip: _tr('تراجع', 'Annuler', 'Undo'),
            onPressed: _undoStack.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
                    IconButton(
            tooltip: _tr('إعادة', 'Rétablir', 'Redo'),
            onPressed: _redoStack.isEmpty ? null : _redo,
            icon: const Icon(Icons.redo),
          ),
                    Builder(
            builder: (btnCtx) => IconButton(
              tooltip: _tr(
                'خيارات النظام',
                'Options système',
                'System options',
              ),
              onPressed: () => _showWorkTypeMenu(btnCtx),
              icon: const Icon(Icons.dashboard_customize_outlined),
            ),
          ),
                    IconButton(
            tooltip: _tr(
              'كيت الزجاج وقواعد الثقوب',
              'Kit verre & perçages',
              'Glass kit & holes',
            ),
            onPressed: _showKitSelectionDialog,
            icon: const Icon(Icons.architecture_outlined),
          ),
                    Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: FilledButton.icon(
              onPressed: _panels.isEmpty
                  ? null
                  : () {
                      final payload = _buildManufacturingPayload();
                      Navigator.pop(context, payload);
                    },
              icon: const Icon(Icons.check, size: 18),
              label: Text(_tr('حفظ', 'Enregistrer', 'Save')),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.cyan.shade900,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 0,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
                    Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: FilledButton.icon(
              onPressed: _panels.isEmpty ? null : _showCostAndQuantityDialog,
              icon: const Icon(Icons.calculate_outlined, size: 18),
              label: Text(
                _tr('الكمية والتكلفة', 'Quantité et Coût', 'Qty & Cost'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 0,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
                    Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: FilledButton.tonalIcon(
              onPressed: _showProfilesAndGasketsDialog,
              icon: const Icon(Icons.view_column_outlined, size: 18),
              label: Text(
                _tr('البروفيلات والجوانات', 'Profilés & joints', 'Profiles & gaskets'),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 0,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
                    Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: FilledButton.tonalIcon(
              onPressed: _showManufacturingSheet,
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text(_tr('ورقة التصنيع', 'Fiche', 'Mfg Sheet')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 0,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
                    IconButton(
            tooltip: _tr('مسح الرسم', 'Effacer le dessin', 'Clear drawing'),
            onPressed: _confirmClearDrawing,
            icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: compact
          ? FloatingActionButton.small(
              tooltip: _tr('أدوات الرسم', 'Outils de dessin', 'Drawing tools'),
              onPressed: _showMobileToolsSheet,
              child: const Icon(Icons.tune),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            children: [
              _buildDrawingToolbar(),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blueGrey.shade900 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.cyan.shade700
                          : Colors.blue.shade200,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _canvasSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      if (!_initialPayloadRestored &&
                          widget.initialPayload != null) {
                        _restoreDrawingFromInitialPayload(_canvasSize);
                      }
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: DragTarget<String>(
                              onWillAcceptWithDetails: (_) => true,
                              onAcceptWithDetails: (details) {
                                final box =
                                    context.findRenderObject() as RenderBox?;
                                if (box != null) {
                                  final local = box.globalToLocal(
                                    details.offset,
                                  );
                                  _handleToolDrop(
                                    details.data,
                                    _canvasPosition(local),
                                  );
                                }
                              },
                              builder: (dragCtx, candidateData, rejectedData) {
                                // Mouse wheel: zoom the glass in and out.
                                return Listener(
                                  onPointerSignal: (event) {
                                    if (event is PointerScrollEvent) {
                                      GestureBinding
                                          .instance
                                          .pointerSignalResolver
                                          .register(event, (event) {
                                            final scroll =
                                                event as PointerScrollEvent;
                                            _changeZoom(
                                              scroll.scrollDelta.dy < 0
                                                  ? 0.1
                                                  : -0.1,
                                            );
                                          });
                                    }
                                  },
                                  child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: _handleCanvasTap,
                                  onLongPressStart: _handleCanvasLongPress,
                                  onDoubleTap: _handleSablageDoubleTap,
                                  onPanStart: _startPanel,
                                  onPanUpdate: _resizePanel,
                                  onPanEnd: _finishPanel,
                                  onPanCancel: () {
                                    _drawStart = null;
                                    _draggingHole = null;
                                    _draggingPanelIndex = null;
                                    setState(() {
                                      _draftPanel = null;
                                      _draftSablageOffsetMm = null;
                                    });
                                  },
                                  child: CustomPaint(
                                    painter: _GlassPanelDrawingPainter(
                                      panels: _panels,
                                      draftPanel: _draftPanel,
                                      draftWidthMm: _draftPanel == null
                                          ? null
                                          : _freehandWidthMmFromPixels(
                                              _draftPanel!.width,
                                            ),
                                      draftHeightMm: _draftPanel == null
                                          ? null
                                          : _freehandHeightMmFromPixels(
                                              _draftPanel!.height,
                                            ),
                                      sablageBands: _sablageBands,
                                      sablageRegions: _sablageRegions,
                                      draftSablageOffsetMm:
                                          _draftSablageOffsetMm,
                                      sablageBandWidthMm: _sablageBandWidth(),
                                      overallHeightMm: _overallHeightMm,
                                      overallWidthMm: _overallWidthMm,
                                      sablageMode: _sablageMode,
                                      zoom: _zoom,
                                      selectedPanelIndex: _selectedPanelIndex,
                                      holeDimensionMode: _holeDimensionMode,
                                      color: isDark
                                          ? Colors.cyan.shade200
                                          : Colors.cyan.shade800,
                                      handleShape: _selectedHandleShape,
                                      handleDesignCode:
                                          _selectedHandleDesignCode,
                                      glassTypeLabel: _glassTypeLabel(
                                        _glassType,
                                      ),
                                      frostedLabel: _tr(
                                        'مصنفر (Sablé)',
                                        'Sablé',
                                        'Frosted',
                                      ),
                                      showSlidingProfiles:
                                          _showProfiles && _isSlidingStraight,
                                      dimensionReferenceLabel:
                                          _holeDimensionReferenceLabel(),
                                      glassThicknessMm: _glassThicknessMm,
                                      gasketEdges: _gasketItems.entries
                                          .where((e) => e.value > 0)
                                          .map((e) => e.key)
                                          .toSet(),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                );
                              },
                            ),
                          ),
                          PositionedDirectional(
                            top: 12,
                            start: 12,
                            child: _buildSideDraggableToolbar(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassManufacturingSheet extends StatelessWidget {
  const _GlassManufacturingSheet({
    required this.payload,
    required this.panels,
    required this.drawingCanvasSize,
    required this.sablageBands,
    this.sablageRegions = const [],
    required this.sablageBandWidthMm,
    required this.overallHeightMm,
    required this.sablageMode,
    required this.workTypeLabel,
    this.allOrderGlassPayloads,
    this.clientName,
    this.orderNumber,
  });

  final Map<String, dynamic> payload;
  final List<_GlassPanel> panels;
  final Size drawingCanvasSize;
  final List<_SablageBand> sablageBands;
  final List<_SablageRegion> sablageRegions;
  final double sablageBandWidthMm;
  final double overallHeightMm;
  final _SablageMode sablageMode;
  final String workTypeLabel;
  final List<Map<String, dynamic>>? allOrderGlassPayloads;
  final String? clientName;
  final String? orderNumber;

  List<Map<String, dynamic>> _resolveAllGlassPayloads() {
    if (allOrderGlassPayloads != null && allOrderGlassPayloads!.isNotEmpty) {
      return allOrderGlassPayloads!;
    }
    return [payload];
  }

  String _tr(BuildContext context, String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  String _tr3(BuildContext context, String ar, String fr, String en) {
    switch (Provider.of<AppSettingsProvider>(context, listen: false).language) {
      case AppLanguage.french:
        return fr;
      case AppLanguage.english:
        return en;
      case AppLanguage.arabic:
        return ar;
    }
  }

  String _value(Object? value, [String fallback = '—']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _mm(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) return '—';
    return '${number.toStringAsFixed(0)} mm';
  }

  String _role(BuildContext context, String role) {
    switch (role) {
      case 'door':
        return _tr3(context, 'باب', 'Porte', 'Door');
      case 'fixed':
        return _tr3(context, 'ثابت', 'Fixe', 'Fixed');
      default:
        return _tr3(context, 'لوح زجاج', 'Panneau de verre', 'Glass panel');
    }
  }

  Widget _spec(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  String _translateGlassType(BuildContext context, Object? type) {
    final val = type?.toString().trim() ?? '';
    final lower = val.toLowerCase();
    if (lower == 'شفاف' ||
        lower == 'clear' ||
        lower == 'clair' ||
        lower == 'transparent') {
      return _tr3(context, 'شفاف', 'Transparent', 'Clear');
    }
    if (lower == 'ملون' || lower == 'teinté' || lower == 'tinted') {
      return _tr3(context, 'ملون', 'Teinté', 'Tinted');
    }
    if (lower == 'عاكس' || lower == 'réfléchissant' || lower == 'reflective') {
      return _tr3(context, 'عاكس', 'Réfléchissant', 'Reflective');
    }
    if (lower == 'مصفح' || lower == 'feuilleté' || lower == 'laminated') {
      return _tr3(context, 'مصفح', 'Feuilleté', 'Laminated');
    }
    if (lower == 'معتّم' || lower == 'opaque') {
      return _tr3(context, 'معتّم', 'Opaque', 'Opaque');
    }
    if (lower == 'مرآة' || lower == 'mirror' || lower == 'miroir') {
      return _tr3(context, 'مرآة', 'Miroir', 'Mirror');
    }
    if (lower == 'شفاف إضافي' || lower == 'extra-clair') {
      return _tr3(context, 'شفاف إضافي', 'Extra-clair', 'Extra clear');
    }
    if (lower == 'ساتان' || lower == 'satiné') {
      return _tr3(context, 'ساتان (مثلّج)', 'Satiné', 'Satin (acid-etched)');
    }
    if (lower == 'مطبوع' || lower == 'imprimé') {
      return _tr3(context, 'مطبوع', 'Imprimé', 'Patterned');
    }
    return val.isEmpty ? '—' : val;
  }

  String _translateEdgeFinish(BuildContext context, Object? finish) {
    final val = finish?.toString().trim() ?? '';
    final lower = val.toLowerCase();
    if (lower.contains('extra') ||
        lower.contains('جداً') ||
        lower.contains('très')) {
      return _tr3(context, 'ناعم جداً', 'Très poli', 'Extra smooth');
    }
    if (lower.contains('smooth') ||
        lower.contains('ناعم') ||
        lower.contains('poli')) {
      return _tr3(context, 'ناعم (بولي)', 'Poli', 'Polished');
    }
    return val.isEmpty ? '—' : val;
  }

  Widget _panelDetails(
    BuildContext context,
    _GlassPanel panel,
    int index, {
    String? sideLabel,
  }) {
    int startHoleNum = 1;
    for (int p = 0; p < index; p++) {
      startHoleNum += panels[p].holes.length;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.cyan.shade800,
                foregroundColor: Colors.white,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_role(context, panel.role)} — ${_mm(panel.widthMm)} × ${_mm(panel.heightMm)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    if (sideLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          sideLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.cyan.shade900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: panel.holes.isEmpty
                      ? Colors.grey.shade100
                      : Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: panel.holes.isEmpty
                        ? Colors.grey.shade300
                        : Colors.deepOrange.shade200,
                  ),
                ),
                child: Text(
                  panel.holes.isEmpty
                      ? _tr3(context, 'بدون ثقوب', 'Sans perçage', 'No holes')
                      : '${panel.holes.length} ${_tr3(context, 'ثقوب', 'perçages', 'holes')}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: panel.holes.isEmpty
                        ? Colors.grey.shade700
                        : Colors.deepOrange.shade800,
                  ),
                ),
              ),
            ],
          ),
          if (panel.holes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (var hIdx = 0; hIdx < panel.holes.length; hIdx++) ...[
                  Builder(
                    builder: (context) {
                      final hole = panel.holes[hIdx];
                      final holeNum = startHoleNum + hIdx;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBE9E7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.deepOrange.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade700,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#$holeNum',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Ø${hole.diameterMm.toStringAsFixed(0)} mm',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.deepOrange.shade900,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '(X: ${hole.xMm.toStringAsFixed(0)} mm, Y: ${hole.yMm.toStringAsFixed(0)} mm)',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF37474F),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxCanvasWidth = math.max(drawingCanvasSize.width, 420.0).toDouble();
    final maxCanvasHeight = math
        .max(drawingCanvasSize.height, 300.0)
        .toDouble();
    final isFrosted = sablageMode != _SablageMode.none;
    final tempered = payload['glassTempered'] == true
        ? _tr3(context, 'نعم', 'Oui', 'Yes')
        : _tr3(context, 'لا', 'Non', 'No');

    final sortedPanels = List<_GlassPanel>.from(panels)
      ..sort((a, b) => a.rect.left.compareTo(b.rect.left));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr3(
            context,
            'ورقة تصنيع الزجاج',
            'Fiche de fabrication du verre',
            'Glass manufacturing sheet',
          ),
        ),
        backgroundColor: Colors.cyan.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _tr3(
              context,
              'معاينة وطباعة ورقة التصنيع (PDF)',
              'Aperçu & impression fiche PDF',
              'Preview & Print PDF Sheet',
            ),
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GlassFabricationPreviewScreen(
                    payloads: [payload],
                    clientName: clientName ?? '',
                    orderNumber: orderNumber ?? '',
                  ),
                ),
              );
            },
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              final all = _resolveAllGlassPayloads();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GlassFabricationPreviewScreen(
                    payloads: all,
                    clientName: clientName ?? '',
                    orderNumber: orderNumber ?? '',
                  ),
                ),
              );
            },
            icon: const Icon(
              Icons.layers_rounded,
              color: Colors.white,
              size: 18,
            ),
            label: Text(
              _tr3(
                context,
                'كل زجاج الطلب (${_resolveAllGlassPayloads().length})',
                'Tout le verre (${_resolveAllGlassPayloads().length})',
                'All Order Glass (${_resolveAllGlassPayloads().length})',
              ),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, payload),
            icon: const Icon(Icons.check, color: Colors.white),
            label: Text(
              _tr3(context, 'اعتماد', 'Valider', 'Approve'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _tr3(
                      context,
                      'طلب تصنيع الزجاج',
                      'Demande de fabrication du verre',
                      'Glass manufacturing request',
                    ),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${panels.length} ${_tr3(context, 'قطعة', 'pièce(s)', 'piece(s)')}',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(workTypeLabel, style: const TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                height: math.max(
                  MediaQuery.of(context).size.height * 0.50,
                  480.0,
                ),
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: maxCanvasWidth,
                        height: maxCanvasHeight,
                        child: CustomPaint(
                          painter: _GlassPanelDrawingPainter(
                            panels: panels,
                            draftPanel: null,
                            sablageBands: sablageBands,
                            sablageRegions: sablageRegions,
                            draftSablageOffsetMm: null,
                            sablageBandWidthMm: sablageBandWidthMm,
                            overallHeightMm: overallHeightMm,
                            overallWidthMm:
                                (payload['overallWidthMm'] as num?)
                                    ?.toDouble() ??
                                0.0,
                            sablageMode: sablageMode,
                            zoom: 1.0,
                            selectedPanelIndex: null,
                            holeDimensionMode:
                                payload['holeDimensionMode'] == 'center'
                                ? _HoleDimensionMode.center
                                : _HoleDimensionMode.edge,
                            color: Colors.cyan.shade800,
                            showHandles:
                                false, // المقابض لا تظهر في الفيش دو فابريكاسيون
                            fabricationOnly: true,
                            dimensionReferenceLabel:
                                payload['holeDimensionModeLabel']
                                    ?.toString() ??
                                '',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _tr3(
                context,
                'مواصفات الزجاج',
                'Spécifications du verre',
                'Glass specifications',
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _spec(
                  _tr3(context, 'نوع الزجاج', 'Type de verre', 'Glass type'),
                  _translateGlassType(context, payload['glassType']),
                ),
                _spec(
                  _tr3(context, 'السمك', 'Épaisseur', 'Thickness'),
                  _mm(payload['glassThicknessMm']),
                ),
              ],
            ),
            Row(
              children: [
                _spec(_tr3(context, 'مقسّى', 'Trempé', 'Tempered'), tempered),
                _spec(
                  _tr3(context, 'نوع الحواف', 'Type de chants', 'Edge finish'),
                  _translateEdgeFinish(
                    context,
                    payload['edgeFinishLabel'] ?? payload['edgeFinish'],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                _spec(
                  _tr3(
                    context,
                    'العرض الإجمالي',
                    'Largeur totale',
                    'Overall width',
                  ),
                  _mm(payload['overallWidthMm']),
                ),
                _spec(
                  _tr3(
                    context,
                    'الارتفاع الإجمالي',
                    'Hauteur totale',
                    'Overall height',
                  ),
                  _mm(payload['overallHeightMm']),
                ),
              ],
            ),
            if (isFrosted)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  sablageMode == _SablageMode.full
                      ? _tr3(
                          context,
                          'الصابلاج: تعتيم كامل (سابلانج كامل)',
                          'Sablage : complet',
                          'Frosting: full',
                        )
                      : _tr3(
                          context,
                          'الصابلاج: ${sablageRegions.isNotEmpty ? sablageRegions.length : sablageBands.length} مناطق، عرض الشريط ${_mm(sablageBandWidthMm)}',
                          'Sablage : ${sablageRegions.isNotEmpty ? sablageRegions.length : sablageBands.length} zones, largeur de bande ${_mm(sablageBandWidthMm)}',
                          'Frosting: ${sablageRegions.isNotEmpty ? sablageRegions.length : sablageBands.length} zones, band width ${_mm(sablageBandWidthMm)}',
                        ),
                  style: const TextStyle(color: Colors.blueGrey),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _tr3(
                context,
                'تفاصيل القطع والثقوب',
                'Détail des panneaux et perçages',
                'Panels and holes details',
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (sortedPanels.length == 2 &&
                MediaQuery.of(context).size.width >= 600)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _panelDetails(
                      context,
                      sortedPanels[0],
                      panels.indexOf(sortedPanels[0]),
                      sideLabel: _tr3(
                        context,
                        'الجهة اليسرى (Panneau gauche)',
                        'Côté gauche',
                        'Left side',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _panelDetails(
                      context,
                      sortedPanels[1],
                      panels.indexOf(sortedPanels[1]),
                      sideLabel: _tr3(
                        context,
                        'الجهة اليمنى (Panneau droit)',
                        'Côté droit',
                        'Right side',
                      ),
                    ),
                  ),
                ],
              )
            else
              for (var index = 0; index < sortedPanels.length; index++)
                _panelDetails(
                  context,
                  sortedPanels[index],
                  panels.indexOf(sortedPanels[index]),
                  sideLabel: sortedPanels.length == 2
                      ? (index == 0
                            ? _tr3(
                                context,
                                'الجهة اليسرى (Panneau gauche)',
                                'Côté gauche',
                                'Left side',
                              )
                            : _tr3(
                                context,
                                'الجهة اليمنى (Panneau droit)',
                                'Côté droit',
                                'Right side',
                              ))
                      : null,
                ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, payload),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                _tr3(
                  context,
                  'اعتماد وإضافة إلى الطلب',
                  'Valider et ajouter à la commande',
                  'Approve and add to order',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassPanelDrawingPainter extends CustomPainter {
  const _GlassPanelDrawingPainter({
    required this.panels,
    required this.draftPanel,
    this.draftWidthMm,
    this.draftHeightMm,
    required this.sablageBands,
    this.sablageRegions = const [],
    required this.draftSablageOffsetMm,
    required this.sablageBandWidthMm,
    required this.overallHeightMm,
    this.overallWidthMm = 0.0,
    required this.sablageMode,
    required this.zoom,
    required this.selectedPanelIndex,
    required this.color,
    this.holeDimensionMode = _HoleDimensionMode.edge,
    this.showHandles = true,
    this.fabricationOnly = false,
    this.handleShape = 'round',
    this.handleDesignCode = 'vro_ronde',
    this.glassTypeLabel = '',
    this.frostedLabel = 'S (Sablé)',
    this.showSlidingProfiles = false,
    this.gasketEdges = const {},
    this.dimensionReferenceLabel = '',
    this.glassThicknessMm = 0,
  });

  final List<_GlassPanel> panels;
  final Rect? draftPanel;
  final double? draftWidthMm;
  final double? draftHeightMm;
  final List<_SablageBand> sablageBands;
  final List<_SablageRegion> sablageRegions;
  final double? draftSablageOffsetMm;
  final double sablageBandWidthMm;
  final double overallHeightMm;
  final double overallWidthMm;
  final _SablageMode sablageMode;
  final double zoom;
  final int? selectedPanelIndex;
  final Color color;
  final _HoleDimensionMode holeDimensionMode;
  final bool showHandles;

  /// Fabrication sheet: only the glass, its frosting, the holes with their
  /// diameters and their X/Y distances (no hinges, hardware or reflections).
  final bool fabricationOnly;
  final String handleShape;
  final String handleDesignCode;

  /// The selected glass type in the chosen language, written on every clear
  /// glass area (a frosted area shows [frostedLabel]).
  final String glassTypeLabel;
  final String frostedLabel;

  /// Sliding shower: the U channel under and beside the fixed glass (wall
  /// side) and the top rail the fixed glass enters.
  final bool showSlidingProfiles;

  /// Door edges carrying a gasket ([GlassGasketLocation] values).
  final Set<String> gasketEdges;

  /// Says whether hole distances run to the hole edge or to its centre;
  /// written on the drawing so the measure is never misread.
  final String dimensionReferenceLabel;

  /// Holes breaking the tempered-glass limits for this thickness are
  /// circled in red (0 disables the check).
  final double glassThicknessMm;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(zoom);
    canvas.translate(-size.width / 2, -size.height / 2);
    final glassPaint = Paint()
      ..color = const Color(0xFFB9E5F8).withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;
    final glassBorderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final reflectionPaint = Paint()
      ..color = fabricationOnly
          ? Colors.transparent
          : Colors.white.withValues(alpha: 0.60)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    for (final panel in panels) {
      _paintGlass(
        canvas,
        panel.rect,
        glassPaint,
        glassBorderPaint,
        reflectionPaint,
      );
    }
    if (draftPanel != null) {
      _paintGlass(
        canvas,
        draftPanel!,
        glassPaint,
        glassBorderPaint,
        reflectionPaint,
      );
    }
    // Frosting is an overlay on the glass, so it must be painted after the
    // glass and before the holes/markers.
    _paintSablage(canvas);
    if (!fabricationOnly) {
      if (showSlidingProfiles) _paintSlidingProfiles(canvas);
      if (gasketEdges.isNotEmpty) _paintGaskets(canvas);
    }
    for (final panel in panels) {
      if (!fabricationOnly) _paintHinges(canvas, panel);
      _paintHoles(canvas, panel);
      if (showHandles && !fabricationOnly) {
        _paintHandles(canvas, panel);
      }
      _paintHoleDimensions(canvas, panel);
    }
    _paintOuterAndPanelDimensions(canvas, size);
    _paintHoleIssues(canvas);
    if (selectedPanelIndex != null &&
        selectedPanelIndex! >= 0 &&
        selectedPanelIndex! < panels.length) {
      final selectionPaint = Paint()
        ..color = Colors.deepOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRect(panels[selectedPanelIndex!].rect, selectionPaint);
    }
    canvas.restore();
    if (dimensionReferenceLabel.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: dimensionReferenceLabel,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFFBF360C),
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: math.max(40.0, size.width - 16));
      final origin = Offset(
        size.width - painter.width - 8,
        size.height - painter.height - 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            origin.dx - 6,
            origin.dy - 3,
            painter.width + 12,
            painter.height + 6,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      painter.paint(canvas, origin);
    }
  }

  /// Circles in red the holes too close to the glass edge or to another
  /// hole, or too small, for tempered glass of [glassThicknessMm].
  void _paintHoleIssues(Canvas canvas) {
    if (glassThicknessMm <= 0) return;
    final issues = findTemperedHoleIssues(
      thicknessMm: glassThicknessMm,
      panels: [
        for (final panel in panels)
          (
            widthMm: panel.widthMm,
            heightMm: panel.heightMm,
            holes: [
              for (final hole in panel.holes)
                (
                  xMm: hole.xMm,
                  yMm: hole.yMm,
                  diameterMm: hole.diameterMm,
                  purpose: hole.purpose,
                ),
            ],
          ),
      ],
    );
    if (issues.isEmpty) return;
    final ring = Paint()
      ..color = Colors.red.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final issue in issues) {
      if (issue.panelIndex >= panels.length) continue;
      final panel = panels[issue.panelIndex];
      if (panel.widthMm <= 0 || panel.heightMm <= 0) continue;
      final scaleX = panel.rect.width / panel.widthMm;
      final scaleY = panel.rect.height / panel.heightMm;
      final purposes = issue.purpose.split(' / ').toSet();
      for (final hole in panel.holes.where(
        (h) => purposes.contains(h.purpose),
      )) {
        final center = Offset(
          panel.rect.left + hole.xMm * scaleX,
          panel.rect.top + hole.yMm * scaleY,
        );
        final radius = math.max(
          6.0,
          hole.diameterMm * math.min(scaleX, scaleY) / 2,
        );
        canvas.drawCircle(center, radius + 5, ring);
      }
    }
  }

  void _paintHinges(Canvas canvas, _GlassPanel panel) {
    if (panel.hinges.isEmpty || panel.heightMm <= 0) return;
    final scaleY = panel.heightMm <= 0
        ? 1.0
        : panel.rect.height / panel.heightMm;

    for (final hinge in panel.hinges) {
      final isLeft = hinge.side == 'left';
      final hY = panel.rect.top + hinge.yMm.clamp(0.0, panel.heightMm) * scaleY;
      final hX = isLeft ? panel.rect.left : panel.rect.right;

      final is180 = hinge.hingeType == 'glass_glass_180';
      final pW = is180 ? 28.0 : 16.0;
      const pH = 34.0;
      final center = Offset(isLeft ? hX + (is180 ? 0.0 : pW * 0.25) : hX - (is180 ? 0.0 : pW * 0.25), hY);
      final plateRect = Rect.fromCenter(center: center, width: pW, height: pH);
      final rrect = RRect.fromRectAndRadius(
        plateRect,
        const Radius.circular(3.0),
      );

      final metalPaint = Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFB0BEC5),
            Color(0xFFFFFFFF),
            Color(0xFFCFD8DC),
            Color(0xFF78909C),
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(plateRect);

      canvas.drawRRect(
        rrect.shift(const Offset(1.0, 1.0)),
        Paint()..color = Colors.black26,
      );
      canvas.drawRRect(rrect, metalPaint);

      final border = Paint()
        ..color = const Color(0xFF37474F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(rrect, border);

      // Central pivot line for 180° hinge or side pivot line
      final pivotX = is180 ? plateRect.center.dx : (isLeft ? plateRect.left + 2.0 : plateRect.right - 2.0);
      canvas.drawLine(
        Offset(pivotX, plateRect.top + 3),
        Offset(pivotX, plateRect.bottom - 3),
        Paint()
          ..color = const Color(0xFF263238)
          ..strokeWidth = is180 ? 2.5 : 2.0,
      );

      final screwPaint = Paint()..color = const Color(0xFF263238);
      if (is180) {
        // Double screws on left and right plates
        canvas.drawCircle(Offset(plateRect.left + 5.0, plateRect.top + 8), 1.6, screwPaint);
        canvas.drawCircle(Offset(plateRect.left + 5.0, plateRect.bottom - 8), 1.6, screwPaint);
        canvas.drawCircle(Offset(plateRect.right - 5.0, plateRect.top + 8), 1.6, screwPaint);
        canvas.drawCircle(Offset(plateRect.right - 5.0, plateRect.bottom - 8), 1.6, screwPaint);
      } else {
        final screwX = isLeft ? plateRect.right - 4.0 : plateRect.left + 4.0;
        canvas.drawCircle(Offset(screwX, plateRect.top + 8), 1.7, screwPaint);
        canvas.drawCircle(Offset(screwX, plateRect.bottom - 8), 1.7, screwPaint);
      }

      final fromTop = hinge.yMm <= panel.heightMm / 2;
      final distMm = fromTop ? hinge.yMm : panel.heightMm - hinge.yMm;
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${distMm.toStringAsFixed(0)}',
          style: const TextStyle(
            fontSize: 7.5,
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Colors.white, blurRadius: 2)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelX = isLeft
          ? plateRect.right + 2
          : plateRect.left - textPainter.width - 2;
      textPainter.paint(canvas, Offset(labelX, hY - textPainter.height / 2));
    }
  }

  void _paintHandles(Canvas canvas, _GlassPanel panel) {
    final scaleX = panel.widthMm <= 0 ? 1.0 : panel.rect.width / panel.widthMm;
    final scaleY = panel.heightMm <= 0
        ? 1.0
        : panel.rect.height / panel.heightMm;

    final isSquareModel =
        handleShape == 'square' || handleDesignCode.contains('carre');

    // 1. Vertical Door Handle
    final handleHoles = panel.holes
        .where((h) => h.purpose.startsWith('handle_'))
        .toList();
    if (handleHoles.length == 1) {
      final h = handleHoles.first;
      final center = Offset(
        panel.rect.left + _safeHoleXMm(panel, h, h.diameterMm) * scaleX,
        panel.rect.top + _safeHoleYMm(panel, h, h.diameterMm) * scaleY,
      );

      if (isSquareModel) {
        // Square Knob Button
        final outerRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 14.0, height: 14.0),
          const Radius.circular(1.5),
        );
        final innerRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 11.5, height: 11.5),
          const Radius.circular(1.0),
        );
        canvas.drawRRect(
          outerRRect.shift(const Offset(1.2, 1.2)),
          Paint()..color = Colors.black26,
        );
        final knobGradient = const LinearGradient(
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFCFD8DC),
            Color(0xFF78909C),
            Color(0xFF37474F),
          ],
          stops: [0.0, 0.35, 0.75, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(outerRRect.outerRect);
        canvas.drawRRect(outerRRect, Paint()..shader = knobGradient);
        canvas.drawRRect(innerRRect, Paint()..color = const Color(0xFFB0BEC5));
        canvas.drawRRect(
          outerRRect,
          Paint()
            ..color = const Color(0xFF37474F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      } else {
        // Round Knob Button
        final knobRect = Rect.fromCircle(center: center, radius: 7);
        final knobPaint = Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFCFD8DC), Color(0xFF546E7A)],
            stops: [0.0, 0.6, 1.0],
          ).createShader(knobRect);

        canvas.drawCircle(center, 7, Paint()..color = Colors.black26);
        canvas.drawCircle(center, 6.2, knobPaint);
        canvas.drawCircle(
          center,
          6.2,
          Paint()
            ..color = const Color(0xFF37474F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
        canvas.drawCircle(
          center,
          3.0,
          Paint()
            ..color = const Color(0xFF455A64)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7,
        );
      }
    } else if (handleHoles.length >= 2) {
      final topHole = handleHoles[0].yMm <= handleHoles[1].yMm
          ? handleHoles[0]
          : handleHoles[1];
      final bottomHole = identical(topHole, handleHoles[0])
          ? handleHoles[1]
          : handleHoles[0];

      final handleXMm = _safeHoleXMm(panel, topHole, topHole.diameterMm);
      final holeCenterX = panel.rect.left + handleXMm * scaleX;
      final topHoleCenter = Offset(
        holeCenterX,
        panel.rect.top +
            _safeHoleYMm(panel, topHole, topHole.diameterMm) * scaleY,
      );
      final bottomHoleCenter = Offset(
        holeCenterX,
        panel.rect.top +
            _safeHoleYMm(panel, bottomHole, bottomHole.diameterMm) * scaleY,
      );

      // Determine door side for stand-off direction
      // If handle is close to left edge, stand-offs project to the right
      // If handle is close to right edge, stand-offs project to the left
      final isNearLeftEdge = handleXMm < (panel.widthMm / 2);
      final standoffDir = isNearLeftEdge ? 1.0 : -1.0;

      final standoffLength = 14.0 * standoffDir;
      final barThickness = isSquareModel ? 7.0 : 6.5;
      final barCenterX = holeCenterX + standoffLength;

      if (!isSquareModel) {
        // ==========================================
        // 1. POIGNÉE RO RONDE (Matching the reference photo exactly)
        // ==========================================
        // Circular rosettes on glass
        for (final mountCenter in [topHoleCenter, bottomHoleCenter]) {
          // Rosette drop shadow
          canvas.drawCircle(
            mountCenter.translate(1.0, 1.0),
            6.5,
            Paint()..color = const Color(0x33000000),
          );
          // Rosette collar
          final rosetteGrad = const RadialGradient(
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFCFD8DC),
              Color(0xFF90A4AE),
              Color(0xFF455A64),
            ],
            stops: [0.0, 0.45, 0.8, 1.0],
          ).createShader(Rect.fromCircle(center: mountCenter, radius: 6.2));
          canvas.drawCircle(mountCenter, 6.0, Paint()..shader = rosetteGrad);
          canvas.drawCircle(
            mountCenter,
            6.0,
            Paint()
              ..color = const Color(0xFF37474F)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.7,
          );
        }

        // Horizontal cylindrical standoffs from rosettes to vertical bar
        final standoffTopRect = Rect.fromLTRB(
          standoffDir > 0
              ? topHoleCenter.dx
              : (topHoleCenter.dx + standoffLength),
          topHoleCenter.dy - barThickness / 2,
          standoffDir > 0
              ? (topHoleCenter.dx + standoffLength)
              : topHoleCenter.dx,
          topHoleCenter.dy + barThickness / 2,
        );
        final standoffBottomRect = Rect.fromLTRB(
          standoffDir > 0
              ? bottomHoleCenter.dx
              : (bottomHoleCenter.dx + standoffLength),
          bottomHoleCenter.dy - barThickness / 2,
          standoffDir > 0
              ? (bottomHoleCenter.dx + standoffLength)
              : bottomHoleCenter.dx,
          bottomHoleCenter.dy + barThickness / 2,
        );

        final standoffShader = LinearGradient(
          colors: const [
            Color(0xFFECEFF1),
            Color(0xFFFFFFFF),
            Color(0xFFB0BEC5),
            Color(0xFF455A64),
          ],
          stops: const [0.0, 0.35, 0.75, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );

        for (final sRect in [standoffTopRect, standoffBottomRect]) {
          canvas.drawRect(
            sRect,
            Paint()..shader = standoffShader.createShader(sRect),
          );
          canvas.drawRect(
            sRect,
            Paint()
              ..color = const Color(0xFF37474F)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.6,
          );
        }

        // Continuous tubular C-curve for the handle bar
        final path = Path();
        final cornerRadius = 9.0;
        if (standoffDir > 0) {
          path.moveTo(topHoleCenter.dx, topHoleCenter.dy);
          path.lineTo(barCenterX - cornerRadius, topHoleCenter.dy);
          path.arcToPoint(
            Offset(barCenterX, topHoleCenter.dy + cornerRadius),
            radius: Radius.circular(cornerRadius),
            clockwise: true,
          );
          path.lineTo(barCenterX, bottomHoleCenter.dy - cornerRadius);
          path.arcToPoint(
            Offset(barCenterX - cornerRadius, bottomHoleCenter.dy),
            radius: Radius.circular(cornerRadius),
            clockwise: true,
          );
          path.lineTo(bottomHoleCenter.dx, bottomHoleCenter.dy);
        } else {
          path.moveTo(topHoleCenter.dx, topHoleCenter.dy);
          path.lineTo(barCenterX + cornerRadius, topHoleCenter.dy);
          path.arcToPoint(
            Offset(barCenterX, topHoleCenter.dy + cornerRadius),
            radius: Radius.circular(cornerRadius),
            clockwise: false,
          );
          path.lineTo(barCenterX, bottomHoleCenter.dy - cornerRadius);
          path.arcToPoint(
            Offset(barCenterX + cornerRadius, bottomHoleCenter.dy),
            radius: Radius.circular(cornerRadius),
            clockwise: false,
          );
          path.lineTo(bottomHoleCenter.dx, bottomHoleCenter.dy);
        }

        // Shadow behind the curved tube
        canvas.drawPath(
          path.shift(const Offset(1.5, 1.5)),
          Paint()
            ..color = Colors.black26
            ..style = PaintingStyle.stroke
            ..strokeWidth = barThickness
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

        // Main polished tubular stainless body
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFB0BEC5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = barThickness
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

        // Core highlight along the tube
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = barThickness * 0.42
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

        // Subtle outer outline
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF37474F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = barThickness
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        // Re-stroke internal body to keep contour clean
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFCFD8DC)
            ..style = PaintingStyle.stroke
            ..strokeWidth = barThickness - 1.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = barThickness * 0.35
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      } else {
        // ==========================================
        // 2. POIGNÉE RO CARRÉE (Matching the square reference photo)
        // ==========================================
        // Square rosettes on glass
        for (final mountCenter in [topHoleCenter, bottomHoleCenter]) {
          final rRect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: mountCenter, width: 13.0, height: 13.0),
            const Radius.circular(1.0),
          );
          // Drop shadow
          canvas.drawRRect(
            rRect.shift(const Offset(1.2, 1.2)),
            Paint()..color = const Color(0x33000000),
          );
          // Satin stainless brushed gradient
          final squareRosetteShader = const LinearGradient(
            colors: [
              Color(0xFFECEFF1),
              Color(0xFFCFD8DC),
              Color(0xFF90A4AE),
              Color(0xFF455A64),
            ],
            stops: [0.0, 0.35, 0.75, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rRect.outerRect);
          canvas.drawRRect(rRect, Paint()..shader = squareRosetteShader);
          canvas.drawRRect(
            rRect,
            Paint()
              ..color = const Color(0xFF37474F)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.7,
          );
        }

        // Horizontal square standoffs
        final standoffTopRect = Rect.fromLTRB(
          standoffDir > 0
              ? topHoleCenter.dx
              : (topHoleCenter.dx + standoffLength),
          topHoleCenter.dy - barThickness / 2,
          standoffDir > 0
              ? (topHoleCenter.dx + standoffLength)
              : topHoleCenter.dx,
          topHoleCenter.dy + barThickness / 2,
        );
        final standoffBottomRect = Rect.fromLTRB(
          standoffDir > 0
              ? bottomHoleCenter.dx
              : (bottomHoleCenter.dx + standoffLength),
          bottomHoleCenter.dy - barThickness / 2,
          standoffDir > 0
              ? (bottomHoleCenter.dx + standoffLength)
              : bottomHoleCenter.dx,
          bottomHoleCenter.dy + barThickness / 2,
        );

        // Vertical square main bar
        final barRect = Rect.fromLTRB(
          barCenterX - barThickness / 2,
          topHoleCenter.dy - barThickness / 2,
          barCenterX + barThickness / 2,
          bottomHoleCenter.dy + barThickness / 2,
        );

        final squareShader = const LinearGradient(
          colors: [
            Color(0xFF78909C),
            Color(0xFFCFD8DC),
            Color(0xFFFFFFFF),
            Color(0xFFB0BEC5),
            Color(0xFF37474F),
          ],
          stops: [0.0, 0.25, 0.5, 0.8, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(barRect);

        final barRRect = RRect.fromRectAndRadius(
          barRect,
          const Radius.circular(0.8),
        );
        canvas.drawRRect(
          barRRect.shift(const Offset(1.5, 1.5)),
          Paint()..color = Colors.black26,
        );

        // Draw horizontal legs
        for (final sRect in [standoffTopRect, standoffBottomRect]) {
          final sRRect = RRect.fromRectAndRadius(
            sRect,
            const Radius.circular(0.6),
          );
          canvas.drawRRect(
            sRRect,
            Paint()
              ..shader = const LinearGradient(
                colors: [
                  Color(0xFFECEFF1),
                  Color(0xFFFFFFFF),
                  Color(0xFF90A4AE),
                  Color(0xFF37474F),
                ],
                stops: [0.0, 0.3, 0.7, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(sRect),
          );
          canvas.drawRRect(
            sRRect,
            Paint()
              ..color = const Color(0xFF37474F)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8,
          );
        }

        // Draw vertical square bar
        canvas.drawRRect(barRRect, Paint()..shader = squareShader);
        canvas.drawRRect(
          barRRect,
          Paint()
            ..color = const Color(0xFF37474F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9,
        );
      }
    }

    // 2. Horizontal Towel Handle Bar (if present)
    final towelHoles = panel.holes
        .where((h) => h.purpose.startsWith('towel_'))
        .toList();
    if (towelHoles.length >= 2) {
      final leftHole = towelHoles[0].xMm <= towelHoles[1].xMm
          ? towelHoles[0]
          : towelHoles[1];
      final rightHole = identical(leftHole, towelHoles[0])
          ? towelHoles[1]
          : towelHoles[0];
      final towelYMm = _safeHoleYMm(panel, leftHole, leftHole.diameterMm);
      final towelCenterY = panel.rect.top + towelYMm * scaleY;
      final leftCenter = Offset(
        panel.rect.left +
            _safeHoleXMm(panel, leftHole, leftHole.diameterMm) * scaleX,
        towelCenterY,
      );
      final rightCenter = Offset(
        panel.rect.left +
            _safeHoleXMm(panel, rightHole, rightHole.diameterMm) * scaleX,
        towelCenterY,
      );

      final isSquareTowel =
          handleShape == 'square' || handleDesignCode.contains('carre');

      for (final mountCenter in [leftCenter, rightCenter]) {
        if (isSquareTowel) {
          final rRect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: mountCenter, width: 14.0, height: 14.0),
            const Radius.circular(1.0),
          );
          canvas.drawRRect(
            rRect.shift(const Offset(1.2, 1.2)),
            Paint()..color = const Color(0x33000000),
          );
          canvas.drawRRect(
            rRect,
            Paint()
              ..shader = const LinearGradient(
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFCFD8DC),
                  Color(0xFF78909C),
                  Color(0xFF37474F),
                ],
                stops: [0.0, 0.35, 0.75, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(rRect.outerRect),
          );
          canvas.drawRRect(
            rRect,
            Paint()
              ..color = const Color(0xFF37474F)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8,
          );
        } else {
          canvas.drawCircle(
            mountCenter,
            7.5,
            Paint()..color = const Color(0x33000000),
          );
          final rosetteShader = const RadialGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFB0BEC5), Color(0xFF546E7A)],
            stops: [0.0, 0.6, 1.0],
          ).createShader(Rect.fromCircle(center: mountCenter, radius: 7.0));
          canvas.drawCircle(mountCenter, 6.8, Paint()..shader = rosetteShader);
          canvas.drawCircle(
            mountCenter,
            6.8,
            Paint()
              ..color = const Color(0xFF37474F)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.7,
          );
        }
      }

      // Horizontal bar between rosettes
      const barH = 6.5;
      final towelBarRect = Rect.fromLTRB(
        leftCenter.dx,
        towelCenterY - barH / 2,
        rightCenter.dx,
        towelCenterY + barH / 2,
      );
      final towelRRect = RRect.fromRectAndRadius(
        towelBarRect,
        Radius.circular(isSquareTowel ? 0.8 : 3.25),
      );
      canvas.drawRRect(
        towelRRect.shift(const Offset(1.2, 1.2)),
        Paint()..color = Colors.black26,
      );
      final towelGradient = const LinearGradient(
        colors: [
          Color(0xFFECEFF1),
          Color(0xFFFFFFFF),
          Color(0xFFB0BEC5),
          Color(0xFF37474F),
        ],
        stops: [0.0, 0.35, 0.75, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(towelBarRect);
      canvas.drawRRect(towelRRect, Paint()..shader = towelGradient);
      canvas.drawRRect(
        towelRRect,
        Paint()
          ..color = const Color(0xFF37474F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  void _paintHoles(Canvas canvas, _GlassPanel panel) {
    if (panel.widthMm <= 0 || panel.heightMm <= 0) return;
    final fill = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.deepOrange.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final scaleX = panel.rect.width / panel.widthMm;
    final scaleY = panel.rect.height / panel.heightMm;

    int holeLabelIndex(_GlassHole targetHole) {
      int count = 0;
      for (final p in panels) {
        if (identical(p, panel)) {
          final idx = p.holes.indexOf(targetHole);
          return count + (idx >= 0 ? idx : 0) + 1;
        }
        count += p.holes.length;
      }
      return panel.holes.indexOf(targetHole) + 1;
    }

    canvas.save();
    canvas.clipRect(panel.rect);
    for (final hole in panel.holes) {
      final diameterMm = _safeHoleDiameterMm(panel, hole);
      final center = Offset(
        panel.rect.left + _safeHoleXMm(panel, hole, diameterMm) * scaleX,
        panel.rect.top + _safeHoleYMm(panel, hole, diameterMm) * scaleY,
      );
      final scaledRadius = diameterMm * math.min(scaleX, scaleY) / 2;
      final radius = hole.purpose.startsWith('handle_')
          ? scaledRadius.clamp(2.0, 5.0).toDouble()
          : math.max(3.0, scaledRadius).toDouble();
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, border);

      final holeNum = holeLabelIndex(hole);
      final numPainter = TextPainter(
        text: TextSpan(
          text: '$holeNum',
          style: TextStyle(
            fontSize: math.max(7.5, radius * 0.95).clamp(7.5, 12.0),
            fontWeight: FontWeight.w900,
            color: Colors.deepOrange.shade900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      numPainter.paint(
        canvas,
        center - Offset(numPainter.width / 2, numPainter.height / 2),
      );

      if (holeDimensionMode == _HoleDimensionMode.center && radius > 10) {
        final crossPaint = Paint()
          ..color = Colors.deepOrange.shade800.withValues(alpha: 0.5)
          ..strokeWidth = 0.8;
        canvas.drawLine(
          center - Offset(radius + 2, 0),
          center - Offset(radius - 2, 0),
          crossPaint,
        );
        canvas.drawLine(
          center + Offset(radius - 2, 0),
          center + Offset(radius + 2, 0),
          crossPaint,
        );
        canvas.drawLine(
          center - Offset(0, radius + 2),
          center - Offset(0, radius - 2),
          crossPaint,
        );
        canvas.drawLine(
          center + Offset(0, radius - 2),
          center + Offset(0, radius + 2),
          crossPaint,
        );
      }
    }
    canvas.restore();
  }

  double _safeHoleDiameterMm(_GlassPanel panel, _GlassHole hole) {
    final maxDiameter = math.min(panel.widthMm, panel.heightMm);
    return hole.diameterMm.clamp(0.0, maxDiameter).toDouble();
  }

  double _safeHoleXMm(_GlassPanel panel, _GlassHole hole, double diameterMm) {
    final minimum = diameterMm / 2;
    final maximum = math.max(minimum, panel.widthMm - minimum);
    return hole.xMm.clamp(minimum, maximum).toDouble();
  }

  double _safeHoleYMm(_GlassPanel panel, _GlassHole hole, double diameterMm) {
    final minimum = diameterMm / 2;
    final maximum = math.max(minimum, panel.heightMm - minimum);
    return hole.yMm.clamp(minimum, maximum).toDouble();
  }

  void _paintHoleDimensions(Canvas canvas, _GlassPanel panel) {
    if (panel.widthMm <= 0 || panel.heightMm <= 0) return;
    final scaleX = panel.rect.width / panel.widthMm;
    final scaleY = panel.rect.height / panel.heightMm;
    final dimensionPaint = Paint()
      ..color = Colors.blueGrey.shade700.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final textStyle = const TextStyle(
      fontSize: 9,
      color: Colors.black,
      fontWeight: FontWeight.w700,
      shadows: [
        Shadow(color: Colors.white, blurRadius: 2.5),
        Shadow(color: Colors.white, blurRadius: 2.5),
      ],
    );

    void drawLabel(String value, Offset position) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }

    void drawArrowDimension(Offset from, Offset to, String label) {
      final totalDist = (to - from).distance;
      // A distance too short for arrows (a hole close to the edge, or a
      // zoomed-out drawing) still shows its value, beside the gap, so every
      // hole keeps its X and Y distances from the glass edges.
      if (totalDist < 12) {
        if (totalDist < 0.5) return;
        final isHorizontalGap =
            (to.dx - from.dx).abs() >= (to.dy - from.dy).abs();
        final middle = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
        canvas.drawLine(from, to, dimensionPaint);
        drawLabel(
          label,
          middle + (isHorizontalGap ? const Offset(0, -9) : const Offset(12, 0)),
        );
        return;
      }

      const gap =
          3.5; // Boundary clearance so arrows and lines do not touch elements
      final unit = (to - from) / totalDist;
      final startPoint = from + unit * gap;
      final endPoint = to - unit * gap;
      final lineDist = (endPoint - startPoint).distance;
      if (lineDist < 5) return;

      canvas.drawLine(startPoint, endPoint, dimensionPaint);

      const arrowSize = 5.0;
      const spread = math.pi / 6; // 30 degrees
      final angle = math.atan2(unit.dy, unit.dx);

      void drawHead(Offset tip, double dirAngle) {
        final backAngle = dirAngle + math.pi;
        final p1 = Offset(
          tip.dx + arrowSize * math.cos(backAngle - spread),
          tip.dy + arrowSize * math.sin(backAngle - spread),
        );
        final p2 = Offset(
          tip.dx + arrowSize * math.cos(backAngle + spread),
          tip.dy + arrowSize * math.sin(backAngle + spread),
        );
        canvas
          ..drawLine(tip, p1, dimensionPaint)
          ..drawLine(tip, p2, dimensionPaint);
      }

      // Arrowhead at startPoint points towards `from` (boundary element)
      drawHead(startPoint, angle + math.pi);
      // Arrowhead at endPoint points towards `to` (boundary element)
      drawHead(endPoint, angle);

      final middle = Offset(
        (startPoint.dx + endPoint.dx) / 2,
        (startPoint.dy + endPoint.dy) / 2,
      );
      final isHorizontal = (to.dx - from.dx).abs() >= (to.dy - from.dy).abs();
      if (isHorizontal) {
        drawLabel(label, middle + const Offset(0, -9));
      } else {
        final painter = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final paintRight = (middle.dx + painter.width + 6) <= panel.rect.right;
        final xPos = paintRight ? middle.dx + 6 : middle.dx - painter.width - 6;
        painter.paint(canvas, Offset(xPos, middle.dy - painter.height / 2));
      }
    }

    double holeDiameter(_GlassHole hole) => _safeHoleDiameterMm(panel, hole);

    double holeX(_GlassHole hole) =>
        _safeHoleXMm(panel, hole, holeDiameter(hole));

    double holeY(_GlassHole hole) =>
        _safeHoleYMm(panel, hole, holeDiameter(hole));

    Offset holeCenter(_GlassHole hole) => Offset(
      panel.rect.left + holeX(hole) * scaleX,
      panel.rect.top + holeY(hole) * scaleY,
    );

    double holeRadius(_GlassHole hole) =>
        math.max(3.0, holeDiameter(hole) * math.min(scaleX, scaleY) / 2);

    final sharedTop = _sharedSlidingTop();
    final measurementTop = sharedTop != null && panel.role == 'door'
        ? sharedTop
        : panel.rect.top;
    final measurementHeightMm = sharedTop != null && panel.role == 'door'
        ? overallHeightMm
        : panel.heightMm;
    final topAllowanceMm = (measurementTop - panel.rect.top) / scaleY;

    final processedHoles = <_GlassHole>{};
    final handleHoles = panel.holes
        .where((h) => h.purpose.startsWith('handle_'))
        .toList();
    final towelHoles = panel.holes
        .where((h) => h.purpose.startsWith('towel_'))
        .toList();
    final doorTopHoles = panel.holes
        .where((h) => h.purpose.startsWith('door_top_'))
        .toList();

    int holeLabelIndex(_GlassHole targetHole) {
      int count = 0;
      for (final p in panels) {
        if (identical(p, panel)) {
          final idx = p.holes.indexOf(targetHole);
          return count + (idx >= 0 ? idx : 0) + 1;
        }
        count += p.holes.length;
      }
      return panel.holes.indexOf(targetHole) + 1;
    }

    final isCenterMode = holeDimensionMode == _HoleDimensionMode.center;

    // 1. Grouped Door Handle Holes (vertically aligned)
    if (handleHoles.length == 2) {
      processedHoles.addAll(handleHoles);
      final topHole = handleHoles[0].yMm <= handleHoles[1].yMm
          ? handleHoles[0]
          : handleHoles[1];
      final bottomHole = identical(topHole, handleHoles[0])
          ? handleHoles[1]
          : handleHoles[0];

      // Fix door flip desynchronization: force horizontal alignment on the door
      if ((bottomHole.xMm - topHole.xMm).abs() > 0.5) {
        bottomHole.xMm = topHole.xMm;
      }

      final topCenter = holeCenter(topHole);
      final bottomCenter = Offset(topCenter.dx, holeCenter(bottomHole).dy);
      final topRadius = holeRadius(topHole);

      final xMm = holeX(topHole);
      final leftMm = (xMm - holeDiameter(topHole) / 2).clamp(
        0.0,
        panel.widthMm,
      );
      final rightMm = (panel.widthMm - xMm - holeDiameter(topHole) / 2).clamp(
        0.0,
        panel.widthMm,
      );
      final fromLeft = leftMm <= rightMm;

      // Single horizontal dimension from nearest edge to handle
      final glassEdgeX = fromLeft ? panel.rect.left : panel.rect.right;
      final holeEdgeX = isCenterMode
          ? topCenter.dx
          : (fromLeft ? topCenter.dx - topRadius : topCenter.dx + topRadius);
      final horizValMm = isCenterMode
          ? (fromLeft ? xMm : (panel.widthMm - xMm))
          : (fromLeft ? leftMm : rightMm);
      drawArrowDimension(
        Offset(glassEdgeX, topCenter.dy),
        Offset(holeEdgeX, topCenter.dy),
        horizValMm.toStringAsFixed(0),
      );

      // Single vertical dimension from top to upper handle hole
      final alignedYMm = holeY(topHole) - topAllowanceMm;
      final topMm = (alignedYMm - holeDiameter(topHole) / 2).clamp(
        0.0,
        measurementHeightMm,
      );
      final holeEdgeY = isCenterMode
          ? topCenter.dy
          : (topCenter.dy - topRadius);
      final topValMm = isCenterMode ? alignedYMm : topMm;
      drawArrowDimension(
        Offset(topCenter.dx, measurementTop),
        Offset(topCenter.dx, holeEdgeY),
        topValMm.toStringAsFixed(0),
      );

      // Vertical distance between handle holes (purely vertical entraxe)
      final spacingMm = (holeY(bottomHole) - holeY(topHole)).abs();
      drawArrowDimension(
        Offset(topCenter.dx, topCenter.dy),
        Offset(topCenter.dx, bottomCenter.dy),
        spacingMm.toStringAsFixed(0),
      );

      // Hole labels placed on inner side away from edge dimension line
      final labelSideOffset = fromLeft ? (topRadius + 28) : -(topRadius + 28);
      drawLabel(
        '#${holeLabelIndex(topHole)} Ø ${holeDiameter(topHole).toStringAsFixed(0)}',
        topCenter + Offset(labelSideOffset, 0),
      );
      drawLabel(
        '#${holeLabelIndex(bottomHole)} Ø ${holeDiameter(bottomHole).toStringAsFixed(0)}',
        bottomCenter + Offset(labelSideOffset, 0),
      );
    }

    // 2. Grouped Towel Handle Holes (horizontally aligned)
    if (towelHoles.length == 2) {
      processedHoles.addAll(towelHoles);
      final leftHole = towelHoles[0].xMm <= towelHoles[1].xMm
          ? towelHoles[0]
          : towelHoles[1];
      final rightHole = identical(leftHole, towelHoles[0])
          ? towelHoles[1]
          : towelHoles[0];

      final leftCenter = holeCenter(leftHole);
      final rightCenter = holeCenter(rightHole);
      final leftRadius = holeRadius(leftHole);
      final rightRadius = holeRadius(rightHole);

      final leftDistMm = (holeX(leftHole) - holeDiameter(leftHole) / 2).clamp(
        0.0,
        panel.widthMm,
      );
      final rightDistMm =
          (panel.widthMm - holeX(rightHole) - holeDiameter(rightHole) / 2)
              .clamp(0.0, panel.widthMm);
      final fromLeft = leftDistMm <= rightDistMm;
      final refHole = fromLeft ? leftHole : rightHole;
      final refCenter = fromLeft ? leftCenter : rightCenter;
      final refRadius = fromLeft ? leftRadius : rightRadius;
      final glassEdgeX = fromLeft ? panel.rect.left : panel.rect.right;
      final holeEdgeX = isCenterMode
          ? refCenter.dx
          : (fromLeft ? refCenter.dx - refRadius : refCenter.dx + refRadius);
      final horizValMm = isCenterMode
          ? (fromLeft ? holeX(refHole) : (panel.widthMm - holeX(refHole)))
          : (fromLeft ? leftDistMm : rightDistMm);

      // Single horizontal dimension from nearest edge
      drawArrowDimension(
        Offset(glassEdgeX, refCenter.dy),
        Offset(holeEdgeX, refCenter.dy),
        horizValMm.toStringAsFixed(0),
      );

      // Single vertical dimension from top edge (NOT two duplicate lines)
      final topMm = (holeY(refHole) - holeDiameter(refHole) / 2).clamp(
        0.0,
        panel.heightMm,
      );
      final topHoleEdgeY = isCenterMode
          ? refCenter.dy
          : (refCenter.dy - refRadius);
      final topValMm = isCenterMode ? holeY(refHole) : topMm;
      drawArrowDimension(
        Offset(refCenter.dx, panel.rect.top),
        Offset(refCenter.dx, topHoleEdgeY),
        topValMm.toStringAsFixed(0),
      );

      // Horizontal distance between towel holes (entraxe)
      final spacingMm = (holeX(rightHole) - holeX(leftHole)).abs();
      drawArrowDimension(
        Offset(leftCenter.dx, leftCenter.dy),
        Offset(rightCenter.dx, rightCenter.dy),
        spacingMm.toStringAsFixed(0),
      );

      // Labels below each hole
      drawLabel(
        '#${holeLabelIndex(leftHole)} Ø ${holeDiameter(leftHole).toStringAsFixed(0)}',
        leftCenter + Offset(0, leftRadius + 11),
      );
      drawLabel(
        '#${holeLabelIndex(rightHole)} Ø ${holeDiameter(rightHole).toStringAsFixed(0)}',
        rightCenter + Offset(0, rightRadius + 11),
      );
    }

    // 3. Grouped Door Top Wheel Holes
    if (doorTopHoles.length == 2) {
      processedHoles.addAll(doorTopHoles);
      final leftHole = doorTopHoles[0].xMm <= doorTopHoles[1].xMm
          ? doorTopHoles[0]
          : doorTopHoles[1];
      final rightHole = identical(leftHole, doorTopHoles[0])
          ? doorTopHoles[1]
          : doorTopHoles[0];

      final leftCenter = holeCenter(leftHole);
      final rightCenter = holeCenter(rightHole);
      final leftRadius = holeRadius(leftHole);
      final rightRadius = holeRadius(rightHole);

      // Left wheel horizontal offset
      final leftMm = (holeX(leftHole) - holeDiameter(leftHole) / 2).clamp(
        0.0,
        panel.widthMm,
      );
      final leftHoleEdgeX = isCenterMode
          ? leftCenter.dx
          : (leftCenter.dx - leftRadius);
      final leftValMm = isCenterMode ? holeX(leftHole) : leftMm;
      drawArrowDimension(
        Offset(panel.rect.left, leftCenter.dy),
        Offset(leftHoleEdgeX, leftCenter.dy),
        leftValMm.toStringAsFixed(0),
      );

      // Right wheel horizontal offset
      final rightMm =
          (panel.widthMm - holeX(rightHole) - holeDiameter(rightHole) / 2)
              .clamp(0.0, panel.widthMm);
      final rightHoleEdgeX = isCenterMode
          ? rightCenter.dx
          : (rightCenter.dx + rightRadius);
      final rightValMm = isCenterMode
          ? (panel.widthMm - holeX(rightHole))
          : rightMm;
      drawArrowDimension(
        Offset(panel.rect.right, rightCenter.dy),
        Offset(rightHoleEdgeX, rightCenter.dy),
        rightValMm.toStringAsFixed(0),
      );

      // Single vertical offset from top of door
      final alignedYMm = holeY(leftHole) - topAllowanceMm;
      final topMm = (alignedYMm - holeDiameter(leftHole) / 2).clamp(
        0.0,
        measurementHeightMm,
      );
      final topHoleEdgeY = isCenterMode
          ? leftCenter.dy
          : (leftCenter.dy - leftRadius);
      final topValMm = isCenterMode ? alignedYMm : topMm;
      drawArrowDimension(
        Offset(leftCenter.dx, measurementTop),
        Offset(leftCenter.dx, topHoleEdgeY),
        topValMm.toStringAsFixed(0),
      );

      // Labels below holes
      drawLabel(
        '#${holeLabelIndex(leftHole)} Ø ${holeDiameter(leftHole).toStringAsFixed(0)}',
        leftCenter + Offset(0, leftRadius + 11),
      );
      drawLabel(
        '#${holeLabelIndex(rightHole)} Ø ${holeDiameter(rightHole).toStringAsFixed(0)}',
        rightCenter + Offset(0, rightRadius + 11),
      );
    }

    // 4. Any standalone or ungrouped holes
    for (var index = 0; index < panel.holes.length; index++) {
      final hole = panel.holes[index];
      if (processedHoles.contains(hole)) continue;

      final center = holeCenter(hole);
      final radius = holeRadius(hole);
      final diameterMm = holeDiameter(hole);
      final xMm = holeX(hole);
      final yMm = holeY(hole);
      final leftMm = (xMm - diameterMm / 2).clamp(0.0, panel.widthMm);
      final rightMm = (panel.widthMm - xMm - diameterMm / 2).clamp(
        0.0,
        panel.widthMm,
      );
      final alignedYMm = yMm - topAllowanceMm;
      final topMm = (alignedYMm - diameterMm / 2).clamp(
        0.0,
        measurementHeightMm,
      );
      final bottomMm = (measurementHeightMm - alignedYMm - diameterMm / 2)
          .clamp(0.0, measurementHeightMm);

      final fromLeft = leftMm <= rightMm;
      final holeEdgeX = isCenterMode
          ? center.dx
          : (fromLeft ? center.dx - radius : center.dx + radius);
      final horizValMm = isCenterMode
          ? (fromLeft ? xMm : (panel.widthMm - xMm))
          : (fromLeft ? leftMm : rightMm);
      final glassEdgeX = fromLeft ? panel.rect.left : panel.rect.right;
      drawArrowDimension(
        Offset(glassEdgeX, center.dy),
        Offset(holeEdgeX, center.dy),
        horizValMm.toStringAsFixed(0),
      );

      final fromTop = topMm <= bottomMm;
      final holeEdgeY = isCenterMode
          ? center.dy
          : (fromTop ? center.dy - radius : center.dy + radius);
      final vertValMm = isCenterMode
          ? (fromTop ? alignedYMm : (measurementHeightMm - alignedYMm))
          : (fromTop ? topMm : bottomMm);
      final glassEdgeY = fromTop ? measurementTop : panel.rect.bottom;
      drawArrowDimension(
        Offset(center.dx, glassEdgeY),
        Offset(center.dx, holeEdgeY),
        vertValMm.toStringAsFixed(0),
      );

      drawLabel(
        '#${holeLabelIndex(hole)} Ø ${diameterMm.toStringAsFixed(0)}',
        center + Offset(0, radius + 11),
      );
    }
  }

  /// The fixed panel next to [door] (sharing a vertical edge), if any.
  _GlassPanel? _fixedBeside(_GlassPanel door) {
    _GlassPanel? best;
    var bestGap = double.infinity;
    for (final panel in panels) {
      if (panel.isDoor) continue;
      final gap = math.min(
        (panel.rect.left - door.rect.right).abs(),
        (panel.rect.right - door.rect.left).abs(),
      );
      final overlapsX =
          panel.rect.left < door.rect.right && panel.rect.right > door.rect.left;
      final distance = overlapsX ? 0.0 : gap;
      if (distance < bestGap) {
        bestGap = distance;
        best = panel;
      }
    }
    return best;
  }

  void _paintSlidingProfiles(Canvas canvas) {
    final door = panels.where((p) => p.isDoor).firstOrNull;
    if (door == null) return;
    final fixed = _fixedBeside(door);
    if (fixed == null || fixed.heightMm <= 0) return;
    final scale = fixed.rect.height / fixed.heightMm;
    final insertPx =
        SlidingGlassProfiles.defaultRailInsertionMm * scale;
    final channelPx = math.max(4.0, 22 * scale);
    final railPx = math.max(6.0, 40 * scale);
    final fill = Paint()
      ..color = const Color(0xFF90A4AE).withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = const Color(0xFF455A64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    void drawProfile(Rect rect) {
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, edge);
    }

    // Top rail across the whole opening; the fixed glass enters it.
    final left = panels.map((p) => p.rect.left).reduce(math.min);
    final right = panels.map((p) => p.rect.right).reduce(math.max);
    final railBottom = fixed.rect.top + insertPx;
    drawProfile(Rect.fromLTRB(left, railBottom - railPx, right, railBottom));

    // U channel under the fixed glass.
    drawProfile(
      Rect.fromLTRB(
        fixed.rect.left,
        fixed.rect.bottom - insertPx,
        fixed.rect.right,
        fixed.rect.bottom - insertPx + channelPx,
      ),
    );

    // U channel on the wall side of the fixed glass, below the rail.
    final wallOnLeft = fixed.rect.center.dx < door.rect.center.dx;
    final wallX = wallOnLeft ? fixed.rect.left : fixed.rect.right;
    drawProfile(
      Rect.fromLTRB(
        wallOnLeft ? wallX - channelPx + insertPx : wallX - insertPx,
        railBottom,
        wallOnLeft ? wallX + insertPx : wallX + channelPx - insertPx,
        fixed.rect.bottom - insertPx,
      ),
    );
  }

  void _paintGaskets(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF263238)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final door in panels.where((p) => p.isDoor)) {
      final fixed = _fixedBeside(door);
      final fixedOnLeft =
          fixed != null && fixed.rect.center.dx < door.rect.center.dx;
      final fixedEdgeX = fixed == null
          ? null
          : (fixedOnLeft ? door.rect.left : door.rect.right);
      final wallEdgeX = fixed == null
          ? door.rect.right
          : (fixedOnLeft ? door.rect.right : door.rect.left);
      if (gasketEdges.contains(GlassGasketLocation.doorWall)) {
        canvas.drawLine(
          Offset(wallEdgeX, door.rect.top + 4),
          Offset(wallEdgeX, door.rect.bottom - 4),
          paint,
        );
      }
      if (fixedEdgeX != null &&
          gasketEdges.contains(GlassGasketLocation.doorFixed)) {
        canvas.drawLine(
          Offset(fixedEdgeX, door.rect.top + 4),
          Offset(fixedEdgeX, door.rect.bottom - 4),
          paint,
        );
      }
    }
  }

  void _drawGlassTypeBadge(
    Canvas canvas, {
    required Rect rect,
    required String text,
    bool isFrosted = true,
  }) {
    if (rect.width < 28 || rect.height < 10) return;
    final fontSize = (rect.height < 22) ? 8.5 : 10.5;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
          color: isFrosted
              ? const Color(0xFF263238).withValues(alpha: 0.88)
              : const Color(0xFF00695C).withValues(alpha: 0.78),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (textPainter.width > rect.width - 6) return;

    final badgeCenter = rect.center;
    final badgeRect = Rect.fromCenter(
      center: badgeCenter,
      width: textPainter.width + 12,
      height: textPainter.height + 4,
    );

    // Subtle translucent rounded badge background inside the glass zone
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(3.5)),
      Paint()
        ..color = isFrosted
            ? Colors.white.withValues(alpha: 0.82)
            : const Color(0xFFE0F2F1).withValues(alpha: 0.78),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(3.5)),
      Paint()
        ..color = isFrosted
            ? const Color(0xFF78909C).withValues(alpha: 0.6)
            : const Color(0xFF80CBC4).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    textPainter.paint(
      canvas,
      Offset(
        badgeCenter.dx - textPainter.width / 2,
        badgeCenter.dy - textPainter.height / 2,
      ),
    );
  }

  void _paintSablage(Canvas canvas) {
    if (panels.isEmpty) return;
    if (sablageMode == _SablageMode.none && glassTypeLabel.isNotEmpty) {
      for (final panel in panels) {
        _drawGlassTypeBadge(
          canvas,
          rect: _glassContentRect(panel.rect),
          text: glassTypeLabel,
          isFrosted: false,
        );
      }
      return;
    }
    final paint = Paint()
      ..color = const Color(0xFFB7B7B7).withValues(alpha: 0.78)
      ..style = PaintingStyle.fill;
    if (sablageMode == _SablageMode.full) {
      for (final panel in panels) {
        final glassRect = _glassContentRect(panel.rect);
        canvas.save();
        canvas.clipRect(glassRect);
        canvas.drawRect(glassRect, paint);
        _drawGlassTypeBadge(
          canvas,
          rect: glassRect,
          text: frostedLabel,
          isFrosted: true,
        );
        canvas.restore();
      }
      return;
    }
    if (sablageMode != _SablageMode.decorative || overallHeightMm <= 0) return;
    if (sablageRegions.isNotEmpty) {
      final sharedTop = _sharedSlidingTop();
      for (final region in sablageRegions) {
        for (final panel in panels) {
          final panelHeightMm = panel.heightMm > 0
              ? panel.heightMm
              : overallHeightMm;
          final scale = panel.rect.height / panelHeightMm;
          final glassRect = _glassContentRect(panel.rect);
          final double top;
          final double bottom;
          if (region.fromBottom) {
            top = glassRect.bottom - region.endMm * scale;
            bottom = glassRect.bottom - region.startMm * scale;
          } else {
            top = (sharedTop ?? panel.rect.top) + region.startMm * scale;
            bottom = (sharedTop ?? panel.rect.top) + region.endMm * scale;
          }
          final regionRect = Rect.fromLTRB(
            glassRect.left,
            top,
            glassRect.right,
            bottom,
          ).intersect(glassRect);

          if (regionRect.width <= 0 || regionRect.height <= 0) continue;

          if (region.type == _SablageRegionType.clear) {
            if (regionRect.height >= 26) {
              _drawGlassTypeBadge(
                canvas,
                rect: regionRect,
                text: glassTypeLabel,
                isFrosted: false,
              );
            }
            continue;
          }

          canvas.save();
          canvas.clipRect(glassRect);
          if (region.type == _SablageRegionType.full) {
            canvas.drawRect(regionRect, paint);
            _drawGlassTypeBadge(
              canvas,
              rect: regionRect,
              text: frostedLabel,
              isFrosted: true,
            );
          } else {
            final pitch = region.opaqueBandMm + region.clearBandMm;
            for (
              var offset = region.startMm;
              offset < region.endMm;
              offset += pitch
            ) {
              final bandEnd = math.min(
                offset + region.opaqueBandMm,
                region.endMm,
              );
              final double bandTop;
              final double bandBottom;
              if (region.fromBottom) {
                bandTop = glassRect.bottom - bandEnd * scale;
                bandBottom = glassRect.bottom - offset * scale;
              } else {
                bandTop = (sharedTop ?? panel.rect.top) + offset * scale;
                bandBottom = (sharedTop ?? panel.rect.top) + bandEnd * scale;
              }
              canvas.drawRect(
                Rect.fromLTRB(
                  glassRect.left,
                  bandTop,
                  glassRect.right,
                  bandBottom,
                ).intersect(glassRect),
                paint,
              );
            }
            _drawGlassTypeBadge(
              canvas,
              rect: regionRect,
              text: frostedLabel,
              isFrosted: true,
            );
          }
          canvas.restore();
        }
      }
      return;
    }
    final labelPaint = Paint()
      ..color = Colors.blueGrey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final bands = [
      ...sablageBands,
      if (draftSablageOffsetMm != null)
        _SablageBand(
          offsetMm: draftSablageOffsetMm!,
          widthMm: sablageBandWidthMm,
        ),
    ];
    if (bands.isEmpty) return;

    // In a sliding cabin the door is intentionally 30 mm taller than the
    // fixed panel. Frosting measurements use the fixed panel's top as the
    // common reference, so both pieces receive the motif at the same level.
    final sharedTop = _sharedSlidingTop();

    for (final band in bands) {
      for (final panel in panels) {
        // Convert the band thickness using the physical height of the panel
        // that is actually being painted. Using the overall drawing height
        // here made a 40 mm band look much thicker when a panel's drawing
        // rectangle and the global measurement were not identical.
        final panelHeightMm = panel.heightMm > 0
            ? panel.heightMm
            : overallHeightMm;
        final scale = panel.rect.height / panelHeightMm;
        final measurementTop = sharedTop ?? panel.rect.top;
        final glassRect = _glassContentRect(panel.rect);
        final bandRect = Rect.fromLTWH(
          glassRect.left,
          measurementTop + band.offsetMm * scale,
          glassRect.width,
          band.widthMm.clamp(0.0, panelHeightMm) * scale,
        ).intersect(glassRect);
        if (bandRect.width <= 0 || bandRect.height <= 0) continue;
        canvas.save();
        canvas.clipRect(glassRect);
        canvas.drawRect(bandRect, paint);
        canvas.drawRect(bandRect, labelPaint);
        final bandText = bandRect.height >= 20 ? frostedLabel : 'S';
        _drawGlassTypeBadge(
          canvas,
          rect: bandRect,
          text: bandText,
          isFrosted: true,
        );
        canvas.restore();
      }
    }
  }

  double? _sharedSlidingTop() {
    final fixedPanels = panels.where((panel) => panel.role == 'fixed');
    if (fixedPanels.isEmpty) return null;
    return fixedPanels
        .map((panel) => panel.rect.top)
        .reduce((a, b) => a > b ? a : b);
  }

  void _paintGlass(
    Canvas canvas,
    Rect panel,
    Paint glassPaint,
    Paint glassBorderPaint,
    Paint reflectionPaint,
  ) {
    if (panel.width < 2 || panel.height < 2) return;
    final glassRect = _glassContentRect(panel);

    canvas.drawRect(glassRect, glassPaint);
    canvas.drawRect(glassRect, glassBorderPaint);
    canvas.drawLine(
      Offset(
        glassRect.left + glassRect.width * 0.18,
        glassRect.top + glassRect.height * 0.16,
      ),
      Offset(
        glassRect.left + glassRect.width * 0.32,
        glassRect.top + glassRect.height * 0.40,
      ),
      reflectionPaint,
    );

    // Label clear glass inside the panel without adding clutter outside
    if (sablageMode == _SablageMode.none) {
      _drawGlassTypeBadge(
        canvas,
        rect: Rect.fromCenter(
          center: Offset(glassRect.center.dx, glassRect.bottom - 22),
          width: 80,
          height: 24,
        ),
        text: 'Clair',
        isFrosted: false,
      );
    }
  }

  void _paintOuterAndPanelDimensions(Canvas canvas, Size canvasSize) {
    if (panels.isEmpty) return;

    final dimensionPaint = Paint()
      ..color = Colors.blueGrey.shade700
      ..strokeWidth = 1.1;

    // Single panel: exactly ONE side height (clear side away from handles, at 34px)
    if (panels.length == 1) {
      final panel = panels.first;
      // Top width
      final topY = panel.rect.top - 18 < 4
          ? panel.rect.top + 14
          : panel.rect.top - 18;
      _drawDimension(
        canvas,
        start: Offset(panel.rect.left, topY),
        end: Offset(panel.rect.right, topY),
        label: panel.widthMm.toStringAsFixed(0),
        horizontal: true,
        paint: dimensionPaint,
      );

      // Pick the side that has no handles so it stays completely clear
      final hasLeftHoles = panel.holes.any((h) => h.xMm < panel.widthMm / 2);
      if (hasLeftHoles && panel.rect.right + 44 < canvasSize.width) {
        // Height on RIGHT side only
        _drawDimension(
          canvas,
          start: Offset(panel.rect.right + 24, panel.rect.top),
          end: Offset(panel.rect.right + 24, panel.rect.bottom),
          label: panel.heightMm.toStringAsFixed(0),
          horizontal: false,
          paint: dimensionPaint,
          textOnLeft: false,
        );
      } else {
        final dimensionX = panel.rect.left - 44 > 0
            ? panel.rect.left - 24
            : panel.rect.left + 16;
        _drawDimension(
          canvas,
          start: Offset(dimensionX, panel.rect.top),
          end: Offset(dimensionX, panel.rect.bottom),
          label: panel.heightMm.toStringAsFixed(0),
          horizontal: false,
          paint: dimensionPaint,
          textOnLeft: dimensionX < panel.rect.left,
        );
      }
      return;
    }

    final minLeft = panels.map((p) => p.rect.left).reduce(math.min);
    final maxRight = panels.map((p) => p.rect.right).reduce(math.max);
    final minTop = panels.map((p) => p.rect.top).reduce(math.min);

    final totalWidth = overallWidthMm > 0
        ? overallWidthMm
        : panels.fold<double>(0.0, (s, p) => s + p.widthMm);

    // 1. Overall outer dimensions:
    // Outer total width (above panels)
    final outerTopY = minTop - 34 < 4 ? minTop + 12 : minTop - 34;
    _drawDimension(
      canvas,
      start: Offset(minLeft, outerTopY),
      end: Offset(maxRight, outerTopY),
      label: totalWidth.toStringAsFixed(0),
      horizontal: true,
      paint: dimensionPaint,
    );

    // Outer height on LEFT: use leftmost panel's height, 34px away with text outside (on left)
    final leftPanel = panels.reduce(
      (a, b) => a.rect.left < b.rect.left ? a : b,
    );
    final leftDimensionX = minLeft - 44 > 0 ? minLeft - 24 : minLeft + 14;
    _drawDimension(
      canvas,
      start: Offset(leftDimensionX, leftPanel.rect.top),
      end: Offset(leftDimensionX, leftPanel.rect.bottom),
      label: leftPanel.heightMm.toStringAsFixed(0),
      horizontal: false,
      paint: dimensionPaint,
      textOnLeft: leftDimensionX < minLeft,
    );

    // Outer height on RIGHT: use rightmost panel's height, 34px away with text outside (on right)
    final rightPanel = panels.reduce(
      (a, b) => a.rect.right > b.rect.right ? a : b,
    );
    final rightDimensionX = maxRight + 44 < canvasSize.width
        ? maxRight + 24
        : maxRight - 14;
    _drawDimension(
      canvas,
      start: Offset(rightDimensionX, rightPanel.rect.top),
      end: Offset(rightDimensionX, rightPanel.rect.bottom),
      label: rightPanel.heightMm.toStringAsFixed(0),
      horizontal: false,
      paint: dimensionPaint,
      textOnLeft: rightDimensionX < maxRight,
    );

    // 2. Individual panel width dimensions (above each panel):
    for (final panel in panels) {
      _drawDimension(
        canvas,
        start: Offset(panel.rect.left, panel.rect.top - 14),
        end: Offset(panel.rect.right, panel.rect.top - 14),
        label: panel.widthMm.toStringAsFixed(0),
        horizontal: true,
        paint: dimensionPaint,
      );
    }

    // 3. In case of 3 or more panels, intermediate panels may show height if different:
    if (panels.length >= 3) {
      final sortedPanels = [...panels]
        ..sort((a, b) => a.rect.left.compareTo(b.rect.left));
      for (var i = 1; i < sortedPanels.length - 1; i++) {
        final middle = sortedPanels[i];
        if (middle.heightMm != sortedPanels[i - 1].heightMm ||
            middle.heightMm != sortedPanels[i + 1].heightMm) {
          _drawDimension(
            canvas,
            start: Offset(middle.rect.left + 14, middle.rect.top),
            end: Offset(middle.rect.left + 14, middle.rect.bottom),
            label: middle.heightMm.toStringAsFixed(0),
            horizontal: false,
            paint: dimensionPaint,
          );
        }
      }
    }
  }

  Rect _glassContentRect(Rect panel) {
    final shortSide = panel.width < panel.height ? panel.width : panel.height;
    final inset = (shortSide * 0.04).clamp(2.0, 6.0).toDouble();
    return panel.deflate(inset);
  }

  void _drawDimension(
    Canvas canvas, {
    required Offset start,
    required Offset end,
    required String label,
    required bool horizontal,
    required Paint paint,
    bool textOnLeft = false,
  }) {
    canvas.drawLine(start, end, paint);
    const tick = 4.0;
    if (horizontal) {
      canvas.drawLine(
        start - const Offset(0, tick),
        start + const Offset(0, tick),
        paint,
      );
      canvas.drawLine(
        end - const Offset(0, tick),
        end + const Offset(0, tick),
        paint,
      );
    } else {
      canvas.drawLine(
        start - const Offset(tick, 0),
        start + const Offset(tick, 0),
        paint,
      );
      canvas.drawLine(
        end - const Offset(tick, 0),
        end + const Offset(tick, 0),
        paint,
      );
    }
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.blueGrey,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(color: Colors.white, blurRadius: 2.5),
            Shadow(color: Colors.white, blurRadius: 2.5),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    if (horizontal) {
      text.paint(canvas, midpoint - Offset(text.width / 2, text.height + 3));
    } else {
      canvas.save();
      final tx = textOnLeft
          ? midpoint.dx - text.height - 5
          : midpoint.dx + text.height + 5;
      canvas.translate(tx, midpoint.dy + text.width / 2);
      canvas.rotate(-math.pi / 2);
      text.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GlassPanelDrawingPainter oldDelegate) => true;
}

class _GlassHinge {
  _GlassHinge({
    required this.yMm,
    this.side = 'left',
    this.widthMm = 45.0,
    this.heightMm = 90.0,
    this.hingeType = 'wall_glass',
  });

  double yMm;
  String side;
  double widthMm;
  double heightMm;
  String hingeType; // 'wall_glass', 'glass_glass_180', 'glass_glass_90'

  _GlassHinge copy() => _GlassHinge(
        yMm: yMm,
        side: side,
        widthMm: widthMm,
        heightMm: heightMm,
        hingeType: hingeType,
      );

  Map<String, dynamic> toMap() => {
    'yMm': yMm,
    'side': side,
    'widthMm': widthMm,
    'heightMm': heightMm,
    'hingeType': hingeType,
  };

  factory _GlassHinge.fromMap(Map map) => _GlassHinge(
    yMm: (map['yMm'] as num?)?.toDouble() ?? 200.0,
    side: map['side']?.toString() ?? 'left',
    widthMm: (map['widthMm'] as num?)?.toDouble() ?? 45.0,
    heightMm: (map['heightMm'] as num?)?.toDouble() ?? 90.0,
    hingeType: map['hingeType']?.toString() ?? 'wall_glass',
  );
}

class _GlassPanel {
  _GlassPanel({
    required this.rect,
    required this.widthMm,
    required this.heightMm,
    this.role = 'panel',
    this.holes = const [],
    List<_GlassHinge>? hinges,
  }) : hinges = hinges ?? [];

  Rect rect;
  double widthMm;
  double heightMm;
  String role;
  List<_GlassHole> holes;
  List<_GlassHinge> hinges;

  bool get isDoor =>
      role.toLowerCase().contains('door') ||
      role.toLowerCase().contains('porte') ||
      role.contains('باب') ||
      role.contains('vitrine');

  bool get isFixed => !isDoor;

  _GlassPanel copy() => _GlassPanel(
    rect: rect,
    widthMm: widthMm,
    heightMm: heightMm,
    role: role,
    holes: holes
        .map(
          (hole) => _GlassHole(
            xMm: hole.xMm,
            yMm: hole.yMm,
            diameterMm: hole.diameterMm,
            purpose: hole.purpose,
          ),
        )
        .toList(),
    hinges: hinges.map((h) => h.copy()).toList(),
  );

  /// Door hinge defaults remain editable after the kit is applied.
  void ensureDoorHinges({String hingeSide = 'left'}) {
    if (hinges.isEmpty && isDoor) {
      final topY = math.min(150.0, heightMm / 3);
      final bottomY = math.max(topY + 100.0, heightMm - 150.0);
      final midY = heightMm / 2;
      hinges = [
        _GlassHinge(yMm: topY, side: hingeSide),
        if (heightMm > 1000.0) _GlassHinge(yMm: midY, side: hingeSide),
        _GlassHinge(yMm: bottomY, side: hingeSide),
      ];
    }
  }
}

class _GlassHole {
  _GlassHole({
    required this.xMm,
    required this.yMm,
    required this.diameterMm,
    required this.purpose,
  });

  double xMm;
  double yMm;
  double diameterMm;
  String purpose;

  // Until the kit rules are introduced, every generated hole can be moved
  // and edited individually.
  bool get isMovable => true;
}

class _MovableHoleTarget {
  const _MovableHoleTarget({
    required this.panelIndex,
    required this.holeIndex,
    required this.purpose,
  });

  final int panelIndex;
  final int holeIndex;
  final String purpose;
}

class _HoleOverride {
  const _HoleOverride({
    required this.xMm,
    required this.yMm,
    required this.diameterMm,
  });

  final double xMm;
  final double yMm;
  final double diameterMm;

  _HoleOverride copy() =>
      _HoleOverride(xMm: xMm, yMm: yMm, diameterMm: diameterMm);
}

class _SablageBand {
  const _SablageBand({required this.offsetMm, required this.widthMm});

  final double offsetMm;
  final double widthMm;
}

class _SablageRegion {
  const _SablageRegion({
    required this.type,
    required this.startMm,
    required this.endMm,
    this.fromBottom = true,
    this.opaqueBandMm = 40,
    this.clearBandMm = 40,
  });

  final _SablageRegionType type;
  final double startMm;
  final double endMm;
  final bool fromBottom;
  final double opaqueBandMm;
  final double clearBandMm;

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'startMm': startMm,
    'endMm': endMm,
    'fromBottom': fromBottom,
    'opaqueBandMm': opaqueBandMm,
    'clearBandMm': clearBandMm,
  };

  factory _SablageRegion.fromMap(Map map) {
    final rawType = map['type']?.toString() ?? 'full';
    final type = _SablageRegionType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () => _SablageRegionType.full,
    );
    double number(String key, double fallback) =>
        (map[key] as num?)?.toDouble() ??
        double.tryParse(map[key]?.toString() ?? '') ??
        fallback;
    return _SablageRegion(
      type: type,
      startMm: number('startMm', 0),
      endMm: number('endMm', 0),
      fromBottom: map['fromBottom'] as bool? ?? true,
      opaqueBandMm: number('opaqueBandMm', 40),
      clearBandMm: number('clearBandMm', 40),
    );
  }
}

class _GlassDrawingSnapshot {
  const _GlassDrawingSnapshot({
    required this.panels,
    required this.overallDrawingRect,
    required this.overallWidthMm,
    required this.overallHeightMm,
    required this.sablageBands,
    required this.workType,
    required this.handleEdgeOffsetMm,
    required this.handleSpacingMm,
    required this.handleCenterFromTopMm,
    required this.towelCenterFromLeftMm,
    required this.towelCenterFromTopMm,
    required this.towelSpacingMm,
    required this.doorTopHoleSideOffsetMm,
    required this.doorTopHoleTopOffsetMm,
    required this.showDoorHandle,
    required this.showTowelHandle,
    required this.holeDiameterMm,
    required this.holeOverrides,
    required this.sablageMode,
    required this.sablageRangeMode,
    required this.sablageFromBottom,
    required this.glassThicknessMm,
    required this.doorOnLeft,
    this.holeDimensionMode = _HoleDimensionMode.edge,
    this.edgeFinish = 'smooth',
    this.selectedAccessories = const {},
  });

  factory _GlassDrawingSnapshot.capture({
    required List<_GlassPanel> panels,
    required Rect? overallDrawingRect,
    required double? overallWidthMm,
    required double? overallHeightMm,
    required List<_SablageBand> sablageBands,
    required GlassWorkType workType,
    required double handleEdgeOffsetMm,
    required double handleSpacingMm,
    required double? handleCenterFromTopMm,
    required double? towelCenterFromLeftMm,
    required double? towelCenterFromTopMm,
    required double towelSpacingMm,
    required double doorTopHoleSideOffsetMm,
    required double doorTopHoleTopOffsetMm,
    required bool showDoorHandle,
    required bool showTowelHandle,
    required double holeDiameterMm,
    required Map<String, _HoleOverride> holeOverrides,
    required _SablageMode sablageMode,
    required bool sablageRangeMode,
    required bool sablageFromBottom,
    required double glassThicknessMm,
    required bool doorOnLeft,
    _HoleDimensionMode holeDimensionMode = _HoleDimensionMode.edge,
    String edgeFinish = 'smooth',
    Map<int, int> selectedAccessories = const {},
  }) {
    return _GlassDrawingSnapshot(
      panels: panels.map((panel) => panel.copy()).toList(),
      overallDrawingRect: overallDrawingRect,
      overallWidthMm: overallWidthMm,
      overallHeightMm: overallHeightMm,
      sablageBands: List.of(sablageBands),
      workType: workType,
      handleEdgeOffsetMm: handleEdgeOffsetMm,
      handleSpacingMm: handleSpacingMm,
      handleCenterFromTopMm: handleCenterFromTopMm,
      towelCenterFromLeftMm: towelCenterFromLeftMm,
      towelCenterFromTopMm: towelCenterFromTopMm,
      towelSpacingMm: towelSpacingMm,
      doorTopHoleSideOffsetMm: doorTopHoleSideOffsetMm,
      doorTopHoleTopOffsetMm: doorTopHoleTopOffsetMm,
      showDoorHandle: showDoorHandle,
      showTowelHandle: showTowelHandle,
      holeDiameterMm: holeDiameterMm,
      holeOverrides: holeOverrides.map(
        (key, value) => MapEntry(key, value.copy()),
      ),
      sablageMode: sablageMode,
      sablageRangeMode: sablageRangeMode,
      sablageFromBottom: sablageFromBottom,
      glassThicknessMm: glassThicknessMm,
      doorOnLeft: doorOnLeft,
      holeDimensionMode: holeDimensionMode,
      edgeFinish: edgeFinish,
      selectedAccessories: selectedAccessories,
    );
  }

  final List<_GlassPanel> panels;
  final Rect? overallDrawingRect;
  final double? overallWidthMm;
  final double? overallHeightMm;
  final List<_SablageBand> sablageBands;
  final GlassWorkType workType;
  final double handleEdgeOffsetMm;
  final double handleSpacingMm;
  final double? handleCenterFromTopMm;
  final double? towelCenterFromLeftMm;
  final double? towelCenterFromTopMm;
  final double towelSpacingMm;
  final double doorTopHoleSideOffsetMm;
  final double doorTopHoleTopOffsetMm;
  final bool showDoorHandle;
  final bool showTowelHandle;
  final double holeDiameterMm;
  final Map<String, _HoleOverride> holeOverrides;
  final _SablageMode sablageMode;
  final bool sablageRangeMode;
  final bool sablageFromBottom;
  final double glassThicknessMm;
  final bool doorOnLeft;
  final _HoleDimensionMode holeDimensionMode;
  final String edgeFinish;
  final Map<int, int> selectedAccessories;
}

class _GlassMeasurementDraft {
  _GlassMeasurementDraft({double? width, double? height})
    : widthController = TextEditingController(
        text: width == null ? '' : width.toStringAsFixed(0),
      ),
      heightController = TextEditingController(
        text: height == null ? '' : height.toStringAsFixed(0),
      ),
      widthFocus = FocusNode(),
      heightFocus = FocusNode();

  final TextEditingController widthController;
  final TextEditingController heightController;
  final FocusNode widthFocus;
  final FocusNode heightFocus;

  void dispose() {
    widthController.dispose();
    heightController.dispose();
    widthFocus.dispose();
    heightFocus.dispose();
  }
}

class _SystemThumbnailWidget extends StatelessWidget {
  const _SystemThumbnailWidget({
    required this.systemCode,
    this.width = 110,
    this.height = 100,
  });

  final String systemCode;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCFDCE6)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          if (w <= 10 || h <= 10 || w.isInfinite || h.isInfinite) {
            return const SizedBox.shrink();
          }
          return CustomPaint(
            size: Size(w, h),
            painter: _SystemDiagramPainter(systemCode: systemCode),
          );
        },
      ),
    );
  }
}

class _SystemDiagramPainter extends CustomPainter {
  const _SystemDiagramPainter({required this.systemCode});

  final String systemCode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
    final w = size.width;
    final h = size.height;
    const pad = 8.0;

    final glassPaint = Paint()
      ..color = const Color(0xFFC7E8F8).withOpacity(0.85)
      ..style = PaintingStyle.fill;
    final glassBorder = Paint()
      ..color = const Color(0xFF0288D1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final hingePaint = Paint()
      ..color = const Color(0xFF455A64)
      ..style = PaintingStyle.fill;
    final railPaint = Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    switch (systemCode) {
      case 'coulissante':
        canvas.drawLine(
          const Offset(pad, pad + 6),
          Offset(w - pad, pad + 6),
          railPaint,
        );
        final mid = w / 2;
        final panelH = math.max(10.0, h - pad * 2 - 8);
        final fixedRect = Rect.fromLTWH(
          mid - 4,
          pad + 8,
          math.max(10.0, mid - pad + 4),
          panelH,
        );
        canvas.drawRect(fixedRect, glassPaint);
        canvas.drawRect(fixedRect, glassBorder);
        final doorRect = Rect.fromLTWH(
          pad,
          pad + 8,
          math.max(10.0, mid + 2 - pad),
          panelH,
        );
        canvas.drawRect(doorRect, glassPaint);
        canvas.drawRect(doorRect, glassBorder);
        canvas.drawCircle(Offset(doorRect.left + 12, pad + 6), 3, hingePaint);
        canvas.drawCircle(Offset(doorRect.right - 12, pad + 6), 3, hingePaint);
        canvas.drawLine(
          Offset(doorRect.right - 8, h / 2 - 12),
          Offset(doorRect.right - 8, h / 2 + 12),
          railPaint..strokeWidth = 2,
        );
        break;

      case 'cabine_l':
      case 'cabine_r':
      case 'cabine_porte':
      case 'cabine_fixe_porte':
      default:
        final isCorner =
            systemCode == 'cabine_l' ||
            systemCode == 'cabine_r' ||
            systemCode == 'cabine_fixe_porte';
        final isTwoDoors = systemCode == 'vitrine_2p';
        final isParoi = systemCode == 'paroi_fixe';

        if (isParoi) {
          final pRect = Rect.fromLTWH(
            w * 0.25,
            pad + 10,
            math.max(10.0, w * 0.5),
            math.max(10.0, h - pad * 2 - 10),
          );
          canvas.drawRect(pRect, glassPaint);
          canvas.drawRect(pRect, glassBorder);
          canvas.drawLine(
            Offset(pad + 4, pad + 10),
            Offset(w * 0.5, pad + 10),
            railPaint..strokeWidth = 1.8,
          );
        } else if (isTwoDoors) {
          final halfW = math.max(10.0, (w - pad * 2 - 4) / 2);
          final panelH = math.max(10.0, h - pad * 2 - 6);
          final d1 = Rect.fromLTWH(pad, pad + 6, halfW, panelH);
          final d2 = Rect.fromLTWH(pad + halfW + 4, pad + 6, halfW, panelH);
          canvas.drawRect(d1, glassPaint);
          canvas.drawRect(d1, glassBorder);
          canvas.drawRect(d2, glassPaint);
          canvas.drawRect(d2, glassBorder);
          for (final f in [0.18, 0.5, 0.82]) {
            canvas.drawRect(
              Rect.fromLTWH(d1.left - 2, d1.top + d1.height * f - 4, 4, 8),
              hingePaint,
            );
            canvas.drawRect(
              Rect.fromLTWH(d2.right - 2, d2.top + d2.height * f - 4, 4, 8),
              hingePaint,
            );
          }
          canvas.drawLine(
            Offset(d1.right - 6, h / 2 - 10),
            Offset(d1.right - 6, h / 2 + 10),
            railPaint..strokeWidth = 1.8,
          );
          canvas.drawLine(
            Offset(d2.left + 6, h / 2 - 10),
            Offset(d2.left + 6, h / 2 + 10),
            railPaint..strokeWidth = 1.8,
          );
        } else if (isCorner) {
          final isRightDoor = systemCode == 'cabine_r';
          final doorW = math.max(10.0, (w - pad * 2 - 6) * 0.55);
          final fixedW = math.max(10.0, (w - pad * 2 - 6) * 0.45);
          final panelH = math.max(10.0, h - pad * 2 - 6);

          final fixedRect = isRightDoor
              ? Rect.fromLTWH(pad, pad + 6, fixedW, panelH)
              : Rect.fromLTWH(pad + doorW + 6, pad + 6, fixedW, panelH);
          final doorRect = isRightDoor
              ? Rect.fromLTWH(pad + fixedW + 6, pad + 6, doorW, panelH)
              : Rect.fromLTWH(pad, pad + 6, doorW, panelH);

          canvas.drawRect(fixedRect, glassPaint);
          canvas.drawRect(fixedRect, glassBorder);
          canvas.drawRect(doorRect, glassPaint);
          canvas.drawRect(doorRect, glassBorder);

          final hingeX = isRightDoor ? doorRect.right - 2 : doorRect.left - 2;
          for (final f in [0.18, 0.5, 0.82]) {
            canvas.drawRect(
              Rect.fromLTWH(
                hingeX,
                doorRect.top + doorRect.height * f - 4,
                4,
                8,
              ),
              hingePaint,
            );
          }
          final handleX = isRightDoor ? doorRect.left + 6 : doorRect.right - 6;
          canvas.drawLine(
            Offset(handleX, h / 2 - 12),
            Offset(handleX, h / 2 + 12),
            railPaint..strokeWidth = 2,
          );
        } else {
          final doorW = math.max(10.0, w - pad * 2 - 28);
          final doorH = math.max(10.0, h - pad * 2 - 6);
          final doorRect = Rect.fromLTWH(pad + 14, pad + 6, doorW, doorH);
          canvas.drawRect(doorRect, glassPaint);
          canvas.drawRect(doorRect, glassBorder);
          for (final f in [0.18, 0.5, 0.82]) {
            canvas.drawRect(
              Rect.fromLTWH(
                doorRect.left - 2,
                doorRect.top + doorRect.height * f - 4,
                4,
                8,
              ),
              hingePaint,
            );
          }
          canvas.drawLine(
            Offset(doorRect.right - 8, h / 2 - 14),
            Offset(doorRect.right - 8, h / 2 + 14),
            railPaint..strokeWidth = 2,
          );
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SystemDiagramPainter oldDelegate) =>
      oldDelegate.systemCode != systemCode;
}

/// A hole that breaks a manufacturing limit of tempered glass.
class TemperedHoleIssue {
  const TemperedHoleIssue({
    required this.panelIndex,
    required this.purpose,
    required this.kind,
    required this.valueMm,
    required this.minimumMm,
  });

  final int panelIndex;
  final String purpose;

  /// 'diameter', 'edge' (hole edge to glass edge) or 'spacing' (between two
  /// holes).
  final String kind;
  final double valueMm;
  final double minimumMm;
}

/// Checks holes against the usual tempered-glass limits (EN 12150 practice):
/// diameter at least the glass thickness, and at least twice the thickness
/// between a hole's edge and the glass edge or another hole. Dragging only
/// keeps a hole inside the panel, so a hole touching the edge was accepted
/// and the panel broke in the furnace or was refused by the supplier.
List<TemperedHoleIssue> findTemperedHoleIssues({
  required double thicknessMm,
  required List<
    ({
      double widthMm,
      double heightMm,
      List<({double xMm, double yMm, double diameterMm, String purpose})> holes,
    })
  >
  panels,
}) {
  final issues = <TemperedHoleIssue>[];
  if (thicknessMm <= 0) return issues;
  final minimumGap = 2 * thicknessMm;
  for (var index = 0; index < panels.length; index++) {
    final panel = panels[index];
    final holes = panel.holes;
    for (var i = 0; i < holes.length; i++) {
      final hole = holes[i];
      final radius = hole.diameterMm / 2;
      if (hole.diameterMm + 0.01 < thicknessMm) {
        issues.add(
          TemperedHoleIssue(
            panelIndex: index,
            purpose: hole.purpose,
            kind: 'diameter',
            valueMm: hole.diameterMm,
            minimumMm: thicknessMm,
          ),
        );
      }
      final edgeGap = math.min(
        math.min(hole.xMm - radius, panel.widthMm - hole.xMm - radius),
        math.min(hole.yMm - radius, panel.heightMm - hole.yMm - radius),
      );
      if (edgeGap + 0.01 < minimumGap) {
        issues.add(
          TemperedHoleIssue(
            panelIndex: index,
            purpose: hole.purpose,
            kind: 'edge',
            valueMm: math.max(0, edgeGap),
            minimumMm: minimumGap,
          ),
        );
      }
      for (var j = i + 1; j < holes.length; j++) {
        final other = holes[j];
        final centres = math.sqrt(
          math.pow(hole.xMm - other.xMm, 2) + math.pow(hole.yMm - other.yMm, 2),
        );
        final gap = centres - radius - other.diameterMm / 2;
        if (gap + 0.01 < minimumGap) {
          issues.add(
            TemperedHoleIssue(
              panelIndex: index,
              purpose: '${hole.purpose} / ${other.purpose}',
              kind: 'spacing',
              valueMm: math.max(0, gap),
              minimumMm: minimumGap,
            ),
          );
        }
      }
    }
  }
  return issues;
}

