import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import '../sql_database.dart';
import '../items_produits/glass_systems_rules_screen.dart';

enum GlassWorkType {
  showerCabin,
  vitrineSingleDoor,
  vitrineDoubleDoor,
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
  const TemperedGlassWorkScreen({super.key, this.initialPayload});

  final Map<String, dynamic>? initialPayload;

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
      draftSablageOffsetMm: null,
      sablageBandWidthMm: 40.0,
      overallHeightMm: overallHeightMm,
      overallWidthMm: overallWidthMm,
      sablageMode: sablageMode,
      zoom: 1.0,
      selectedPanelIndex: null,
      holeDimensionMode: holeDimensionMode,
      color: Colors.cyan.shade800,
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
  static const _handleHoleEdgeOffsetMm = 50.0;
  static const _handleHoleSpacingMm = 200.0;
  static const _towelHoleSpacingMm = 450.0;

  bool _showDoorHandle = true;
  bool _showTowelHandle = true;

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
  double _glassThicknessMm = 10.0;
  String _glassType = 'شفاف';
  bool _glassTempered = true;
  String _edgeFinish = 'smooth';
  bool _doorOnLeft = true;
  _HoleDimensionMode _holeDimensionMode = _HoleDimensionMode.edge;
  bool _initialPayloadRestored = false;
  final SqlDatabase _db = SqlDatabase();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _catalogAccessories = [];
  Map<int, int> _selectedAccessories = {};
  String _accDrawerCategory = 'all';
  String _accDrawerSearch = '';

  List<Map<String, dynamic>> _glassKits = [];
  Map<String, dynamic>? _selectedKit;
  List<Map<String, dynamic>> _activeKitHoles = [];
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
          if (_selectedKit == null && kits.isNotEmpty) {
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
      final holes = await _db.getTemperedGlassKitHoles(kitId);
      if (mounted) {
        setState(() => _activeKitHoles = holes);
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
                          setState(() => _selectedKit = kit);
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

  String _glassTypeLabel(String value) {
    return switch (value) {
      'شفاف' => _tr('شفاف', 'Transparent', 'Clear'),
      'ملون' => _tr('ملون', 'Teinté', 'Tinted'),
      'عاكس' => _tr('عاكس', 'Réfléchissant', 'Reflective'),
      'مصفح' => _tr('مصفح', 'Feuilleté', 'Laminated'),
      'معتّم' => _tr('معتّم', 'Opaque', 'Opaque'),
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
      _doorOnLeft = !_doorOnLeft;
      _applySlidingLayout();
    });
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
      for (var holeIndex = 0; holeIndex < panel.holes.length; holeIndex++) {
        final hole = panel.holes[holeIndex];
        if (!hole.isMovable) continue;
        final scaleX = panel.widthMm <= 0
            ? 1.0
            : panel.rect.width / panel.widthMm;
        final scaleY = panel.heightMm <= 0
            ? 1.0
            : panel.rect.height / panel.heightMm;
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
    final hole = panel.holes[target.holeIndex];
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
                    decimal: true,
                  ),
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
    for (final panel in _panels) {
      final panelTopWidthBox = Rect.fromLTRB(
        panel.rect.left - 4,
        panel.rect.top - 30,
        panel.rect.right + 4,
        panel.rect.top,
      );
      if (panelTopWidthBox.contains(position)) {
        _editMeasurements(focusHeight: false);
        return true;
      }
    }
    return false;
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
    if (_sablageMode != _SablageMode.decorative) return;
    _editSablageOptions();
  }

  bool get _sablageEnabled => _sablageMode == _SablageMode.decorative;

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
    _panels
      ..clear()
      ..addAll([
        _GlassPanel(
          rect: doorRect,
          widthMm: doorWidth,
          heightMm: doorHeightMm,
          role: 'door',
          holes: _doorHoles(
            doorWidth,
            doorHeightMm,
            referenceHeightMm: drawnHeightMm,
          ),
        ),
        _GlassPanel(
          rect: fixedRect,
          widthMm: fixedWidth,
          heightMm: drawnHeightMm,
          role: 'fixed',
          holes: _fixedHoles(fixedWidth, drawnHeightMm),
        ),
      ]);
    _selectedPanelIndex = 0;
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
    if (_activeKitHoles.isNotEmpty) {
      for (final h in _activeKitHoles) {
        final minW = (h['min_panel_width_mm'] as num? ?? 0.0).toDouble();
        if (minW > 0 && widthMm < minW) continue;

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
    if (!_showTowelHandle) return [];
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
    return [
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
        ]
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
        if (_showDoorHandle) {
          panel.holes.addAll(
            _doorHoles(
              panel.widthMm,
              panel.heightMm,
            ).where((h) => h.purpose.startsWith('handle_')),
          );
        }
        if (_showTowelHandle) {
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
    hole.xMm = override.xMm
        .clamp(diameter / 2, math.max(diameter / 2, widthMm - diameter / 2))
        .toDouble();
    hole.yMm = override.yMm
        .clamp(diameter / 2, math.max(diameter / 2, heightMm - diameter / 2))
        .toDouble();
    return hole;
  }

  Future<void> _editMovableHole(_MovableHoleTarget target) async {
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
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: label,
                suffixText: 'mm',
                border: const OutlineInputBorder(),
              ),
            );
          }

          return AlertDialog(
            title: Text(_tr('تعديل الثقب', 'Modifier le trou', 'Edit hole')),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
        final updatedHole = _panels[target.panelIndex].holes[target.holeIndex];
        updatedHole.xMm = x;
        updatedHole.yMm = y;
        updatedHole.diameterMm = diameter;
        _holeOverrides[updatedHole.purpose] = _HoleOverride(
          xMm: x,
          yMm: y,
          diameterMm: diameter,
        );
      });
    }
  }

  Future<void> _editHandleFromToolbar() async {
    if (!_isSlidingStraight || _panels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'اختر كابين دوش منزلقة وارسمها أولاً.',
              'Choisissez une cabine coulissante et dessinez-la d’abord.',
              'Choose a sliding shower cabin and draw it first.',
            ),
          ),
        ),
      );
      return;
    }
    final target = _findHoleByPurpose('handle_top');
    if (target != null) await _editMovableHole(target);
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

            TextField measurementField(
              TextEditingController controller,
              String label, {
              ValueChanged<String>? onChanged,
              bool autofocus = false,
              TextInputAction textInputAction = TextInputAction.next,
            }) {
              return TextField(
                controller: controller,
                autofocus: autofocus,
                textInputAction: textInputAction,
                onSubmitted: (_) => submit(),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: label,
                  suffixText: 'mm',
                  border: const OutlineInputBorder(),
                ),
                onChanged: onChanged,
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

    final selected = await showMenu<_SablageMode>(
      context: context,
      position: position,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<_SablageMode>(
          value: _SablageMode.none,
          height: 38,
          child: Row(
            children: [
              const Icon(Icons.clear, size: 19, color: Colors.grey),
              const SizedBox(width: 10),
              Text(_tr('بدون سابلاج', 'Sans sablage', 'No frosting')),
            ],
          ),
        ),
        PopupMenuItem<_SablageMode>(
          value: _SablageMode.full,
          height: 38,
          child: Row(
            children: [
              const Icon(Icons.format_color_fill, size: 19, color: Colors.cyan),
              const SizedBox(width: 10),
              Text(
                _tr('تعتيم كامل (Full)', 'Sablage complet', 'Full frosting'),
              ),
            ],
          ),
        ),
        PopupMenuItem<_SablageMode>(
          value: _SablageMode.decorative,
          height: 38,
          child: Row(
            children: [
              const Icon(
                Icons.view_agenda_outlined,
                size: 19,
                color: Colors.deepOrange,
              ),
              const SizedBox(width: 10),
              Text(
                _tr(
                  'تعتيم ديكور (Decorative)',
                  'Sablage décoratif',
                  'Decorative frosting',
                ),
              ),
            ],
          ),
        ),
      ],
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
        builder: (context, setDialogState) => AlertDialog(
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
                        _tr('سابلاج كامل', 'Sablage complet', 'Full frosting'),
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
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? type),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: start,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'البداية من الأسفل',
                      'Début depuis le bas',
                      'Start from bottom',
                    ),
                    suffixText: 'mm',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: end,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'النهاية من الأسفل',
                      'Fin depuis le bas',
                      'End from bottom',
                    ),
                    suffixText: 'mm',
                  ),
                ),
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
                if (from == null ||
                    to == null ||
                    to <= from ||
                    from < 0 ||
                    to > _overallHeightMm ||
                    band <= 0 ||
                    gap < 0)
                  return;
                Navigator.pop(
                  dialogContext,
                  _SablageRegion(
                    type: type,
                    startMm: from,
                    endMm: to,
                    opaqueBandMm: band,
                    clearBandMm: gap,
                  ),
                );
              },
              child: Text(_tr('إضافة', 'Ajouter', 'Add')),
            ),
          ],
        ),
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

    final filtered = _catalogAccessories.where((item) {
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
                            (item['price'] as num?)?.toDouble() ?? 0.0;
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

  Future<void> _showCostAndQuantityDialog() async {
    double totalAreaSqm = 0.0;
    double totalPerimeterM = 0.0;
    for (final panel in _panels) {
      final area = (panel.widthMm / 1000.0) * (panel.heightMm / 1000.0);
      final perim = 2 * (panel.widthMm + panel.heightMm) / 1000.0;
      totalAreaSqm += area;
      totalPerimeterM += perim;
    }

    double glassRatePerSqm =
        3500.0 +
        (_glassThicknessMm >= 10
            ? 1000.0
            : (_glassThicknessMm >= 8 ? 500.0 : 0.0));
    double chantRatePerM = _edgeFinish == 'extra_smooth' ? 600.0 : 350.0;
    double sablageRatePerSqm = 1200.0;
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
            final price = (handleItem['price'] as num?)?.toDouble() ?? 4500.0;
            appliedAccessories.add({
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
            final price = (towelItem['price'] as num?)?.toDouble() ?? 4800.0;
            appliedAccessories.add({
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
            final price = (railItem['price'] as num?)?.toDouble() ?? 16500.0;
            appliedAccessories.add({
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
            final price = (hingeItem['price'] as num?)?.toDouble() ?? 3800.0;
            appliedAccessories.add({
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
            final price = (pivotItem['price'] as num?)?.toDouble() ?? 14000.0;
            appliedAccessories.add({
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

          for (final entry in _selectedAccessories.entries) {
            final item = _catalogAccessories.firstWhere(
              (a) => a['id'] == entry.key,
              orElse: () => <String, dynamic>{},
            );
            if (item.isNotEmpty && entry.value > 0) {
              final price = (item['price'] as num?)?.toDouble() ?? 0.0;
              final tot = price * entry.value;
              appliedAccessories.add({
                'name': item['name'] ?? '',
                'qty': entry.value,
                'unit': item['unit'] ?? 'piece',
                'price': price,
                'total': tot,
              });
              accessoriesTotal += tot;
            }
          }

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
                                '${glassRatePerSqm.toStringAsFixed(0)} DZD',
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
                              '${chantRatePerM.toStringAsFixed(0)} DZD/m',
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
                                '${sablageRatePerSqm.toStringAsFixed(0)} DZD/m²',
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
                                  '${(acc['price'] as double).toStringAsFixed(0)} DZD',
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
    bool showDropdownArrow = true,
  }) {
    return SizedBox(
      width: width,
      height: 52,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: Colors.cyan.withValues(alpha: 0.10),
          highlightColor: Colors.cyan.withValues(alpha: 0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueGrey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 17, color: Colors.cyan.shade800),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1,
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
                        size: 19,
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
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E2E8)),
      ),
      child: Scrollbar(
        controller: _toolbarScrollController,
        thumbVisibility: true,
        interactive: true,
        thickness: 4,
        radius: const Radius.circular(8),
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _toolbarScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToolbarDropdownField(
                label: _tr('الأبعاد', 'Dimensions', 'Dimensions'),
                value: _measurementSummary(),
                icon: Icons.straighten,
                width: 180,
                showDropdownArrow: false,
                onTap: _editMeasurements,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 135,
                height: 52,
                child: DropdownButtonFormField<_HoleDimensionMode>(
                  value: _holeDimensionMode,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.black87,
                    size: 20,
                  ),
                  decoration: _toolbarFieldDecoration(
                    _tr('أبعاد الثقوب', 'Cotation trous', 'Hole dims'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: _HoleDimensionMode.edge,
                      child: Text(
                        _tr('حافة الثقب', 'Bord du trou', 'Hole edge'),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    DropdownMenuItem(
                      value: _HoleDimensionMode.center,
                      child: Text(
                        _tr('مركز الثقب', 'Centre du trou', 'Hole center'),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode == null || mode == _holeDimensionMode) return;
                    setState(() => _holeDimensionMode = mode);
                  },
                ),
              ),
              if (_isSlidingStraight) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 105,
                  height: 52,
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
                      fontSize: 12.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _toolbarFieldDecoration(
                      _tr('عرض الباب', 'Larg. porte', 'Door width'),
                      suffixText: 'mm',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 52,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.blueGrey.shade200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: _tr('قلب الباب', 'Inverser la porte', 'Swap door'),
                    onPressed: _toggleSlidingSides,
                    icon: const Icon(Icons.swap_horiz, color: Colors.black87),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              _buildToolbarDropdownField(
                label: _tr('المقابض', 'Poignées', 'Handles'),
                value: _handlesButtonLabel(),
                icon: Icons.pan_tool_outlined,
                width: 140,
                onTap: _showHandlesSelectionDialog,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                height: 52,
                child: DropdownButtonFormField<double>(
                  value: _glassThicknessMm,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.black87,
                    size: 20,
                  ),
                  decoration: _toolbarFieldDecoration(
                    _tr('سمك الزجاج', 'Épaisseur', 'Thickness'),
                  ),
                  items: const [10.0, 8.0, 6.0, 5.0, 4.0]
                      .map(
                        (thickness) => DropdownMenuItem<double>(
                          value: thickness,
                          child: Text(
                            '${thickness.toStringAsFixed(0)} mm',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value == _glassThicknessMm) return;
                    _pushHistory();
                    setState(() => _glassThicknessMm = value);
                    _loadSystemRules();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                height: 52,
                child: DropdownButtonFormField<String>(
                  value: _glassType,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.black87,
                    size: 20,
                  ),
                  decoration: _toolbarFieldDecoration(
                    _tr('نوع الزجاج', 'Type de vitrage', 'Glass type'),
                  ),
                  items: const ['شفاف', 'ملون', 'عاكس', 'مصفح', 'معتّم']
                      .map(
                        (type) => DropdownMenuItem<String>(
                          value: type,
                          child: Text(
                            _glassTypeLabel(type),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value == _glassType) return;
                    setState(() => _glassType = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              _buildToolbarDropdownField(
                label: _tr('التقسية', 'Trempe', 'Tempering'),
                value: _glassTempered
                    ? _tr('مقسّى', 'Trempé', 'Tempered')
                    : _tr('عادي', 'Normal', 'Standard'),
                icon: Icons.shield_outlined,
                width: 115,
                onTap: () => setState(() => _glassTempered = !_glassTempered),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                height: 52,
                child: DropdownButtonFormField<String>(
                  value: _edgeFinish,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.black87,
                    size: 20,
                  ),
                  decoration: _toolbarFieldDecoration(
                    _tr('نوع الحواف', 'Type de chants', 'Edge type'),
                  ),
                  items: const ['smooth', 'extra_smooth']
                      .map(
                        (finish) => DropdownMenuItem<String>(
                          value: finish,
                          child: Text(
                            _edgeFinishLabel(finish),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value == _edgeFinish) return;
                    setState(() => _edgeFinish = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (btnCtx) => _buildToolbarDropdownField(
                  label: _tr('الصابلاج', 'Sablage', 'Frosting'),
                  value: switch (_sablageMode) {
                    _SablageMode.full => _tr(
                      'تعتيم كامل',
                      'Sablage complet',
                      'Full frosting',
                    ),
                    _SablageMode.decorative => _tr(
                      'تعتيم ديكور (${_sablageRegions.isNotEmpty ? _sablageRegions.length : _sablageBands.length})',
                      'Sablage décoratif (${_sablageRegions.isNotEmpty ? _sablageRegions.length : _sablageBands.length})',
                      'Decorative (${_sablageRegions.isNotEmpty ? _sablageRegions.length : _sablageBands.length})',
                    ),
                    _SablageMode.none => _tr(
                      'بدون سابلاج',
                      'Sans sablage',
                      'None',
                    ),
                  },
                  icon: _sablageMode == _SablageMode.full
                      ? Icons.format_color_fill
                      : Icons.brush_outlined,
                  width: 145,
                  onTap: () => _showSablageMenu(btnCtx),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 4, right: 4),
                height: 52,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.blueGrey.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: _tr(
                    'إضافة منطقة سابلاج',
                    'Ajouter une zone de sablage',
                    'Add frosting zone',
                  ),
                  onPressed: _addSablageRegion,
                  icon: const Icon(
                    Icons.add_box_outlined,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (_sablageBands.isNotEmpty || _sablageRegions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 4, right: 4),
                  height: 52,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.blueGrey.shade200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: _tr(
                      'مسح الصابلاج',
                      'Effacer le sablage',
                      'Clear sablage',
                    ),
                    onPressed: () {
                      _pushHistory();
                      setState(() {
                        _sablageBands.clear();
                        _sablageRegions.clear();
                      });
                    },
                    icon: const Icon(Icons.clear_all, color: Colors.black87),
                  ),
                ),
              const SizedBox(width: 8),
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
                    width: 140,
                    onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                  );
                },
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (btnCtx) => _buildToolbarDropdownField(
                  label: _tr(
                    'خيارات النظام',
                    'Options système',
                    'System options',
                  ),
                  value: _currentSystemName,
                  icon: Icons.dashboard_customize_outlined,
                  width: 175,
                  onTap: () => _showWorkTypeMenu(btnCtx),
                ),
              ),
              const SizedBox(width: 8),
              _buildToolbarDropdownField(
                label: _tr('كيت الزجاج', 'Kit verre', 'Glass Kit'),
                value:
                    _selectedKit?['name']?.toString() ??
                    _tr('اختيار كيت', 'Choisir kit', 'Select kit'),
                icon: Icons.architecture_outlined,
                width: 160,
                onTap: _showKitSelectionDialog,
              ),
              const VerticalDivider(width: 12),
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.blueGrey.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 38,
                      ),
                      tooltip: _tr('تصغير', 'Zoom arrière', 'Zoom out'),
                      onPressed: () => _changeZoom(-0.1),
                      icon: const Icon(
                        Icons.zoom_out,
                        size: 18,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${(_zoom * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 38,
                      ),
                      tooltip: _tr('تكبير', 'Zoom avant', 'Zoom in'),
                      onPressed: () => _changeZoom(0.1),
                      icon: const Icon(
                        Icons.zoom_in,
                        size: 18,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _handleCanvasTap,
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
                            draftSablageOffsetMm: _draftSablageOffsetMm,
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
                          ),
                          child: const SizedBox.expand(),
                        ),
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

  Widget _panelDetails(BuildContext context, _GlassPanel panel, int index) {
    final holes = panel.holes
        .map(
          (hole) =>
              'Ø${hole.diameterMm.toStringAsFixed(0)} mm (${hole.xMm.toStringAsFixed(0)} × ${hole.yMm.toStringAsFixed(0)} mm)',
        )
        .join('، ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: Colors.cyan.shade700,
            foregroundColor: Colors.white,
            child: Text('${index + 1}'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_role(context, panel.role)} — ${_mm(panel.widthMm)} × ${_mm(panel.heightMm)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  panel.holes.isEmpty
                      ? _tr3(context, 'بدون ثقوب', 'Sans perçage', 'No holes')
                      : '${_tr3(context, 'الثقوب', 'Perçages', 'Holes')}: $holes',
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
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
    final maxCanvasWidth = math.max(drawingCanvasSize.width, 420.0).toDouble();
    final maxCanvasHeight = math
        .max(drawingCanvasSize.height, 300.0)
        .toDouble();
    final isFrosted = sablageMode != _SablageMode.none;
    final tempered = payload['glassTempered'] == true
        ? _tr(context, 'نعم')
        : _tr(context, 'لا');

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(context, 'ورقة تصنيع الزجاج')),
        backgroundColor: Colors.cyan.shade800,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, payload),
            icon: const Icon(Icons.check, color: Colors.white),
            label: Text(
              _tr(context, 'اعتماد'),
              style: TextStyle(color: Colors.white),
            ),
          ),
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
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: Container(
                height: 430,
                padding: const EdgeInsets.all(8),
                color: Colors.white,
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
                        sablageMode: sablageMode,
                        zoom: 1.0,
                        selectedPanelIndex: null,
                        holeDimensionMode:
                            payload['holeDimensionMode'] == 'center'
                            ? _HoleDimensionMode.center
                            : _HoleDimensionMode.edge,
                        color: Colors.cyan.shade800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _tr(context, 'مواصفات الزجاج'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _spec(
                  _tr3(context, 'نوع الزجاج', 'Type de verre', 'Glass type'),
                  _value(payload['glassType']),
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
                  _value(payload['edgeFinishLabel'] ?? payload['edgeFinish']),
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
                          'الصابلاج: تعتيم كامل',
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
            const SizedBox(height: 6),
            Text(
              _tr3(
                context,
                'تفاصيل القطع والثقوب',
                'Détail des panneaux et perçages',
                'Panels and holes details',
              ),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < panels.length; index++)
              _panelDetails(context, panels[index], index),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, payload),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(_tr(context, 'اعتماد وإضافة إلى الطلب')),
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
      ..color = Colors.white.withValues(alpha: 0.60)
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
    for (final panel in panels) {
      _paintHoles(canvas, panel);
      _paintHoleDimensions(canvas, panel);
    }
    _paintOuterAndPanelDimensions(canvas);
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
    canvas.save();
    canvas.clipRect(panel.rect);
    for (final hole in panel.holes) {
      final diameterMm = _safeHoleDiameterMm(panel, hole);
      final center = Offset(
        panel.rect.left + _safeHoleXMm(panel, hole, diameterMm) * scaleX,
        panel.rect.top + _safeHoleYMm(panel, hole, diameterMm) * scaleY,
      );
      final radius = math
          .max(3.0, diameterMm * math.min(scaleX, scaleY) / 2)
          .toDouble();
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, border);

      if (holeDimensionMode == _HoleDimensionMode.center) {
        final crossPaint = Paint()
          ..color = Colors.deepOrange.shade800
          ..strokeWidth = 1.0;
        canvas.drawLine(
          center - const Offset(2.5, 0),
          center + const Offset(2.5, 0),
          crossPaint,
        );
        canvas.drawLine(
          center - const Offset(0, 2.5),
          center + const Offset(0, 2.5),
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
      if (totalDist < 12) return;

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

      final topCenter = holeCenter(topHole);
      final bottomCenter = holeCenter(bottomHole);
      final topRadius = holeRadius(topHole);
      final bottomRadius = holeRadius(bottomHole);

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

      // Vertical distance between handle holes
      final spacingMm = isCenterMode
          ? (holeY(bottomHole) - holeY(topHole))
          : (holeY(bottomHole) -
                    holeY(topHole) -
                    (holeDiameter(topHole) + holeDiameter(bottomHole)) / 2)
                .clamp(0.0, double.infinity);
      final startBetweenY = isCenterMode
          ? topCenter.dy
          : (topCenter.dy + topRadius);
      final endBetweenY = isCenterMode
          ? bottomCenter.dy
          : (bottomCenter.dy - bottomRadius);
      drawArrowDimension(
        Offset(topCenter.dx, startBetweenY),
        Offset(bottomCenter.dx, endBetweenY),
        spacingMm.toStringAsFixed(0),
      );

      // Hole labels placed on inner side away from edge dimension line
      final labelSideOffset = fromLeft ? (topRadius + 28) : -(topRadius + 28);
      drawLabel(
        '#${panel.holes.indexOf(topHole) + 1} Ø ${holeDiameter(topHole).toStringAsFixed(0)}',
        topCenter + Offset(labelSideOffset, 0),
      );
      drawLabel(
        '#${panel.holes.indexOf(bottomHole) + 1} Ø ${holeDiameter(bottomHole).toStringAsFixed(0)}',
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

      // Horizontal distance between towel holes
      final spacingMm = isCenterMode
          ? (holeX(rightHole) - holeX(leftHole))
          : (holeX(rightHole) -
                    holeX(leftHole) -
                    (holeDiameter(leftHole) + holeDiameter(rightHole)) / 2)
                .clamp(0.0, double.infinity);
      final startBetweenX = isCenterMode
          ? leftCenter.dx
          : (leftCenter.dx + leftRadius);
      final endBetweenX = isCenterMode
          ? rightCenter.dx
          : (rightCenter.dx - rightRadius);
      drawArrowDimension(
        Offset(startBetweenX, leftCenter.dy),
        Offset(endBetweenX, rightCenter.dy),
        spacingMm.toStringAsFixed(0),
      );

      // Labels below each hole
      drawLabel(
        '#${panel.holes.indexOf(leftHole) + 1} Ø ${holeDiameter(leftHole).toStringAsFixed(0)}',
        leftCenter + Offset(0, leftRadius + 11),
      );
      drawLabel(
        '#${panel.holes.indexOf(rightHole) + 1} Ø ${holeDiameter(rightHole).toStringAsFixed(0)}',
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
        '#${panel.holes.indexOf(leftHole) + 1} Ø ${holeDiameter(leftHole).toStringAsFixed(0)}',
        leftCenter + Offset(0, leftRadius + 11),
      );
      drawLabel(
        '#${panel.holes.indexOf(rightHole) + 1} Ø ${holeDiameter(rightHole).toStringAsFixed(0)}',
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
        '#${index + 1} Ø ${diameterMm.toStringAsFixed(0)}',
        center + Offset(0, radius + 11),
      );
    }
  }

  void _paintSablage(Canvas canvas) {
    if (panels.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFFB7B7B7).withValues(alpha: 0.78)
      ..style = PaintingStyle.fill;
    if (sablageMode == _SablageMode.full) {
      for (final panel in panels) {
        final glassRect = _glassContentRect(panel.rect);
        canvas.save();
        canvas.clipRect(glassRect);
        canvas.drawRect(glassRect, paint);
        canvas.restore();
      }
      return;
    }
    if (sablageMode != _SablageMode.decorative || overallHeightMm <= 0) return;
    if (sablageRegions.isNotEmpty) {
      final sharedTop = _sharedSlidingTop();
      for (final region in sablageRegions) {
        if (region.type == _SablageRegionType.clear) continue;
        for (final panel in panels) {
          final panelHeightMm = panel.heightMm > 0
              ? panel.heightMm
              : overallHeightMm;
          final scale = panel.rect.height / panelHeightMm;
          final glassRect = _glassContentRect(panel.rect);
          final top = (sharedTop ?? panel.rect.top) + region.startMm * scale;
          final bottom = (sharedTop ?? panel.rect.top) + region.endMm * scale;
          canvas.save();
          canvas.clipRect(glassRect);
          if (region.type == _SablageRegionType.full) {
            canvas.drawRect(
              Rect.fromLTRB(
                glassRect.left,
                top,
                glassRect.right,
                bottom,
              ).intersect(glassRect),
              paint,
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
              canvas.drawRect(
                Rect.fromLTRB(
                  glassRect.left,
                  (sharedTop ?? panel.rect.top) + offset * scale,
                  glassRect.right,
                  (sharedTop ?? panel.rect.top) + bandEnd * scale,
                ).intersect(glassRect),
                paint,
              );
            }
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
  }

  void _paintOuterAndPanelDimensions(Canvas canvas) {
    if (panels.isEmpty) return;

    final dimensionPaint = Paint()
      ..color = Colors.blueGrey.shade700
      ..strokeWidth = 1.1;

    // Single panel: exactly ONE side height (clear side away from handles, at 34px)
    if (panels.length == 1) {
      final panel = panels.first;
      // Top width
      _drawDimension(
        canvas,
        start: Offset(panel.rect.left, panel.rect.top - 18),
        end: Offset(panel.rect.right, panel.rect.top - 18),
        label: panel.widthMm.toStringAsFixed(0),
        horizontal: true,
        paint: dimensionPaint,
      );

      // Pick the side that has no handles so it stays completely clear
      final hasLeftHoles = panel.holes.any((h) => h.xMm < panel.widthMm / 2);
      if (hasLeftHoles) {
        // Height on RIGHT side only
        _drawDimension(
          canvas,
          start: Offset(panel.rect.right + 34, panel.rect.top),
          end: Offset(panel.rect.right + 34, panel.rect.bottom),
          label: panel.heightMm.toStringAsFixed(0),
          horizontal: false,
          paint: dimensionPaint,
          textOnLeft: false,
        );
      } else {
        // Height on LEFT side only
        _drawDimension(
          canvas,
          start: Offset(panel.rect.left - 34, panel.rect.top),
          end: Offset(panel.rect.left - 34, panel.rect.bottom),
          label: panel.heightMm.toStringAsFixed(0),
          horizontal: false,
          paint: dimensionPaint,
          textOnLeft: true,
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
    _drawDimension(
      canvas,
      start: Offset(minLeft, minTop - 34),
      end: Offset(maxRight, minTop - 34),
      label: totalWidth.toStringAsFixed(0),
      horizontal: true,
      paint: dimensionPaint,
    );

    // Outer height on LEFT: use leftmost panel's height, 34px away with text outside (on left)
    final leftPanel = panels.reduce(
      (a, b) => a.rect.left < b.rect.left ? a : b,
    );
    _drawDimension(
      canvas,
      start: Offset(minLeft - 34, leftPanel.rect.top),
      end: Offset(minLeft - 34, leftPanel.rect.bottom),
      label: leftPanel.heightMm.toStringAsFixed(0),
      horizontal: false,
      paint: dimensionPaint,
      textOnLeft: true,
    );

    // Outer height on RIGHT: use rightmost panel's height, 34px away with text outside (on right)
    final rightPanel = panels.reduce(
      (a, b) => a.rect.right > b.rect.right ? a : b,
    );
    _drawDimension(
      canvas,
      start: Offset(maxRight + 34, rightPanel.rect.top),
      end: Offset(maxRight + 34, rightPanel.rect.bottom),
      label: rightPanel.heightMm.toStringAsFixed(0),
      horizontal: false,
      paint: dimensionPaint,
      textOnLeft: false,
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

class _GlassPanel {
  _GlassPanel({
    required this.rect,
    required this.widthMm,
    required this.heightMm,
    this.role = 'panel',
    this.holes = const [],
  });

  Rect rect;
  double widthMm;
  double heightMm;
  String role;
  List<_GlassHole> holes;
  bool get isDoor =>
      role.toLowerCase().contains('door') ||
      role.toLowerCase().contains('porte') ||
      role.contains('باب');

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
  );
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
    this.opaqueBandMm = 40,
    this.clearBandMm = 40,
  });

  final _SablageRegionType type;
  final double startMm;
  final double endMm;
  final double opaqueBandMm;
  final double clearBandMm;

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'startMm': startMm,
    'endMm': endMm,
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
      );

  final TextEditingController widthController;
  final TextEditingController heightController;

  void dispose() {
    widthController.dispose();
    heightController.dispose();
  }
}
