// Force compile sync trigger
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/material_consumption_screen.dart';
import 'profile_selector_dialog.dart';
import '../../widgets/section_image.dart';
import 'package:database_data/sql_database.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/services/cloud_sync_service.dart';

enum _FrameResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class WindowView extends StatefulWidget {
  final WindowModel model;
  final String systemMode;

  const WindowView({super.key, required this.model, this.systemMode = ''});

  @override
  State<WindowView> createState() => _WindowViewState();
}

class _WindowViewState extends State<WindowView> {
  static const double _minUserScale = 0.5;
  static const double _maxUserScale = 5.0;
  static const double _zoomStep = 1.15;

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get isSlidingSupported {
    if (widget.systemMode == 'mixed') return true;
    final type = activeSeriesForSystem?.type;
    if (type == 'Frappe' || type == 'frappe') return false;
    return widget.systemMode == 'sliding';
  }

  AluminumSeries? get activeSeriesForSystem {
    if (widget.systemMode == 'sliding') {
      return widget.model.activeSlidingSeries;
    }
    if (widget.systemMode == 'mixed') {
      final zone = widget.model.selectedZone;
      if (zone != null && zone.content == ZoneContent.slidingSash) {
        return widget.model.activeSlidingSeries;
      }
    }
    return widget.model.activeSeries;
  }

  bool _isDraggingHandle = false;
  bool _isDraggingHinge = false;
  bool _isDraggingSlantLeft = false;
  bool _isDraggingSlantRight = false;
  bool _isDraggingArch = false;
  bool _isDraggingDoubleSashDivider = false;
  bool _isDraggingSashDivision = false;
  String? _draggedSashZoneId;
  bool _draggedSashIsRight = false;
  bool _draggedSashIsHorizontal = false;
  int _draggedSashIndex = 0;
  bool _isDraggingDecor = false;
  int _draggedDecorIndex = -1;
  bool _draggedDecorIsHorizontal = true;
  String? _draggedDecorZoneId;
  _FrameResizeHandle? _draggedFrameResizeHandle;
  String? _draggedFrameZoneId;
  bool _frameResizeHistorySaved = false;
  final ScrollController _glassScrollController = ScrollController();
  final ScrollController _leftDrawerScrollController = ScrollController();
  final TextEditingController _leftSashWidthController =
  TextEditingController();
  final FocusNode _leftSashFocusNode = FocusNode();
  late final TextEditingController _positionCtrl;

  double _userScale = 1.0;
  double _baseUserScale = 1.0;
  Offset _userPan = Offset.zero;
  Offset _baseUserPan = Offset.zero;
  Offset _focalPointStart = Offset.zero;

  bool _isDrawerOpen = false;
  bool _isLeftDrawerOpen = false;

  /// On Windows Flutter excludes a mouse from drag scrolling by default.
  /// Both drawing drawers contain horizontal option rows, so enable mouse and
  /// trackpad dragging here without changing the phone touch experience.
  ScrollBehavior _drawerScrollBehavior(
    BuildContext context, {
    bool scrollbars = true,
  }) {
    return ScrollConfiguration.of(context).copyWith(
      scrollbars: scrollbars,
      dragDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      },
    );
  }

  double _leftDrawerHandleTop = 15.0;
  double _rightDrawerHandleTop = 15.0;

  String? _previousSelectionKey;
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  // 🎨 Paintbrush Quick Apply Mode State
  GlassFinish? _activePaintFinish;
  GlassStructure? _activePaintStructure;
  ZoneContent? _activePaintZoneContent;
  int? _activePaintSlidingSashesCount;
  bool _activePaintCellSash = false;
  bool _activePaintCellPanel = false;
  Timer? _paintbrushTimer;
  int _paintbrushSecondsLeft = 0;
  Timer? _drawingTimer;

  GlassSpecification _tempGlassSpec = const GlassSpecification();
  GlassSpecification? _activePaintGlassSpec;

  int _activeBottomTab = 0; // 0: شائع, 1: إطار, 2: ورقة, 3: عامود, 4: زجاج
  bool _isBottomPanelExpanded = false;

  // ── حالة الضغط على منطقة الستار ──
  bool _isShutterSelected = false;
  int _activeShutterTab =
  0; // 0: شائع, 1: الصندوق, 2: الشفرات, 3: السكك, 4: نوع الستار
  List<Map<String, dynamic>> _shutterLamesOptions = [];
  List<Map<String, dynamic>> _shutterCoulisseOptions = [];
  List<Map<String, dynamic>> _shutterCaissonOptions = [];
  bool _loadingShutterOptions = false;
  StreamSubscription<String>? _catalogSubscription;
  Timer? _catalogReloadDebounce;

  List<Map<String, dynamic>> _frameProfiles = [];
  List<Map<String, dynamic>> _sashProfiles = [];
  int? _loadedSeriesId;
  bool _loadingAvailableProfiles = false;

  Future<void> _loadAvailableProfiles() async {
    final seriesId = activeSeriesForSystem?.id;
    if (seriesId == null) {
      if (mounted) {
        setState(() {
          _frameProfiles = [];
          _sashProfiles = [];
          _loadedSeriesId = null;
        });
      }
      return;
    }
    if (_loadedSeriesId == seriesId) return;
    if (_loadingAvailableProfiles) return;
    _loadingAvailableProfiles = true;
    try {
      final db = SqlDatabase();
      final myDb = await db.db;
      if (myDb == null) return;

      // Load Sections
      final allSections = await myDb.query(
        'Sections',
        where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
        whereArgs: [seriesId],
      );

      final legacyFrames = allSections.where((s) {
        final ty = s['type'].toString().toLowerCase().trim();
        return ty.contains('frame') ||
            ty.contains('cadre') ||
            ty.contains('إطار') ||
            ty.contains('فريم');
      }).toList();

      final legacySashes = allSections.where((s) {
        final ty = s['type'].toString().toLowerCase().trim();
        return ty.contains('sash') ||
            ty.contains('ouvrant') ||
            ty.contains('ضلفة') ||
            ty.contains('ساش');
      }).toList();

      // New series definitions make the mapping explicit.  Until a manager
      // configures a legacy series we retain the previous type-name fallback.
      final configuredFrames = await db.getDesignSectionsForRoles(
        seriesId,
        const ['frame', 'frame_extension'],
      );
      final configuredSashes = await db.getDesignSectionsForRoles(
        seriesId,
        const ['sash', 'sash_extension'],
      );
      final frames = configuredFrames.isEmpty
          ? legacyFrames
          : configuredFrames;
      final sashes = configuredSashes.isEmpty
          ? legacySashes
          : configuredSashes;

      // Ignore an old result when the user has already switched series.
      if (!mounted || activeSeriesForSystem?.id != seriesId) return;
      setState(() {
        _frameProfiles = frames;
        _sashProfiles = sashes;
        _loadedSeriesId = seriesId;
      });
    } finally {
      _loadingAvailableProfiles = false;
      // Only queue another load when the user changed the series while this
      // request was in flight. Retrying the same failed request in a tight
      // loop would make the drawing page appear to crash temporarily.
      if (mounted &&
          activeSeriesForSystem?.id != null &&
          activeSeriesForSystem?.id != seriesId &&
          activeSeriesForSystem?.id != _loadedSeriesId) {
        unawaited(_loadAvailableProfiles());
      }
    }
  }

  DecorationImage? _getWoodTextureImage(Map<String, dynamic> dbColor) {
    final name = dbColor['name'].toString().toLowerCase();
    final cleanName = name
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');

    final isWood =
        cleanName.contains('خشب') ||
            cleanName.contains('wood') ||
            cleanName.contains('bois') ||
            cleanName.contains('╪«╪┤╪¿') ||
            cleanName.contains('desert') ||
            cleanName.contains('ديزر') ||
            cleanName.contains('ديزير') ||
            cleanName.contains('oak') ||
            cleanName.contains('اوك') ||
            cleanName.contains('chene') ||
            cleanName.contains('chêne') ||
            cleanName.contains('noyer') ||
            cleanName.contains('acajou') ||
            cleanName.contains('شين') ||
            cleanName.contains('نويا') ||
            cleanName.contains('اكاجو') ||
            cleanName.contains('بوا') ||
            cleanName.contains('faux') ||
            cleanName.contains('فو') ||
            cleanName.contains('antique') ||
            cleanName.contains('انتيك') ||
            cleanName.contains('onteak') ||
            cleanName.contains('╪º┘å╪¬┘è┘â') ||
            cleanName.contains('╪»┘è╪▓╪▒') ||
            cleanName.contains('d0') ||
            cleanName.contains('دي زيرو') ||
            cleanName.contains('بلوط') ||
            cleanName.contains('di zero');

    if (!isWood) return null;

    String assetPath = 'assets/images/wood_texture.png';
    if (cleanName.contains('d0') ||
        cleanName.contains('oak') ||
        cleanName.contains('اوك') ||
        cleanName.contains('شين') ||
        cleanName.contains('chene') ||
        cleanName.contains('chêne') ||
        cleanName.contains('بلوط') ||
        cleanName.contains('دي زيرو') ||
        cleanName.contains('di zero') ||
        cleanName.contains('desert') ||
        cleanName.contains('ديزر') ||
        cleanName.contains('ديزير') ||
        cleanName.contains('╪»┘è╪▓╪▒')) {
      assetPath = 'assets/images/wood_texture_d0.png';
    } else if (cleanName.contains('antique') ||
        cleanName.contains('انتيك') ||
        cleanName.contains('onteak') ||
        cleanName.contains('╪º┘å╪¬┘è┘â')) {
      assetPath = 'assets/images/wood_texture_antique.png';
    } else if (cleanName.contains('grey') ||
        cleanName.contains('gray') ||
        cleanName.contains('gris') ||
        cleanName.contains('رمادي')) {
      assetPath = 'assets/images/wood_texture_grey.png';
    } else if (cleanName.contains('dark') ||
        cleanName.contains('daكن') ||
        cleanName.contains('fonce') ||
        cleanName.contains('foncé')) {
      assetPath = 'assets/images/wood_texture_dark.png';
    }

    return DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover);
  }

  /// Reveals only the next part of the glass form, and only if the user is
  /// already at the end of the visible form. In particular, picking the glass
  /// structure at the top must never throw the drawer to its bottom.
  void _autoScrollDrawer() {
    if (!_leftDrawerScrollController.hasClients) return;

    final position = _leftDrawerScrollController.position;
    const revealThreshold = 72.0;
    if (position.maxScrollExtent <= 0 ||
        position.extentAfter > revealThreshold) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_leftDrawerScrollController.hasClients) return;
      final updatedPosition = _leftDrawerScrollController.position;
      final amountToReveal =
          updatedPosition.extentAfter.clamp(0.0, 96.0).toDouble();
      if (amountToReveal <= 0) return;
      _leftDrawerScrollController.animateTo(
        updatedPosition.pixels + amountToReveal,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _startPaintbrushMode({
    GlassFinish? finish,
    GlassStructure? structure,
    ZoneContent? zoneContent,
    int? slidingSashesCount,
    bool cellSash = false,
    bool cellPanel = false,
    GlassSpecification? glassSpec,
  }) {
    _paintbrushTimer?.cancel();
    setState(() {
      _activePaintFinish = finish;
      _activePaintStructure = structure;
      _activePaintZoneContent = zoneContent;
      _activePaintSlidingSashesCount = slidingSashesCount;
      _activePaintCellSash = cellSash;
      _activePaintCellPanel = cellPanel;
      _activePaintGlassSpec = glassSpec;
      _paintbrushSecondsLeft = 10;
    });

    _paintbrushTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_paintbrushSecondsLeft > 1) {
          _paintbrushSecondsLeft--;
        } else {
          _paintbrushSecondsLeft = 0;
          _activePaintFinish = null;
          _activePaintStructure = null;
          _activePaintZoneContent = null;
          _activePaintSlidingSashesCount = null;
          _activePaintCellSash = false;
          _activePaintCellPanel = false;
          _activePaintGlassSpec = null;
          timer.cancel();
        }
      });
    });
  }

  void _cancelPaintbrushMode() {
    _paintbrushTimer?.cancel();
    setState(() {
      _paintbrushSecondsLeft = 0;
      _activePaintFinish = null;
      _activePaintStructure = null;
      _activePaintZoneContent = null;
      _activePaintGlassSpec = null;
      _activePaintSlidingSashesCount = null;
      _activePaintCellSash = false;
      _activePaintCellPanel = false;
    });
  }

  String? _getTappedCellId(WindowZone tappedZ, Offset modelPos) {
    bool isDouble = tappedZ.content == ZoneContent.doubleSash;
    bool isSingle = tappedZ.content == ZoneContent.singleSash;
    bool isSliding = tappedZ.content == ZoneContent.slidingSash;
    if (isDouble || isSingle || isSliding) {
      double splitX =
          tappedZ.boundary.left +
              tappedZ.boundary.width * tappedZ.doubleSashRatio;
      bool isRight = isDouble && (modelPos.dx > splitX);
      Rect sashR = tappedZ.boundary;
      if (isDouble) {
        final sep = 4.0;
        sashR = isRight
            ? Rect.fromLTRB(
          splitX + sep / 2,
          tappedZ.boundary.top,
          tappedZ.boundary.right,
          tappedZ.boundary.bottom,
        )
            : Rect.fromLTRB(
          tappedZ.boundary.left,
          tappedZ.boundary.top,
          splitX - sep / 2,
          tappedZ.boundary.bottom,
        );
      }
      final sashT =
          tappedZ.sashThickness ??
              widget.model.getSectionThickness('sash', fallback: 45.0);
      final glassR = sashR.deflate(sashT);
      if (glassR.contains(modelPos)) {
        int currentInnerH = isRight ? tappedZ.rightInnerH : tappedZ.innerH;
        int currentInnerV = isRight ? tappedZ.rightInnerV : tappedZ.innerV;
        double cellW = glassR.width / (currentInnerV + 1);
        double cellH = glassR.height / (currentInnerH + 1);
        int col = ((modelPos.dx - glassR.left) / cellW)
            .clamp(0, currentInnerV)
            .toInt();
        int row = ((modelPos.dy - glassR.top) / cellH)
            .clamp(0, currentInnerH)
            .toInt();
        String sidePrefix = isDouble ? (isRight ? 'right' : 'left') : 'main';
        return '${sidePrefix}_cell_${row}_$col';
      }
    } else {
      // Non-sash zone (fixed glass, etc.)
      final glassR = tappedZ.boundary;
      if (glassR.contains(modelPos)) {
        int currentInnerH = tappedZ.innerH;
        int currentInnerV = tappedZ.innerV;
        double cellW = glassR.width / (currentInnerV + 1);
        double cellH = glassR.height / (currentInnerH + 1);
        int col = ((modelPos.dx - glassR.left) / cellW)
            .clamp(0, currentInnerV)
            .toInt();
        int row = ((modelPos.dy - glassR.top) / cellH)
            .clamp(0, currentInnerH)
            .toInt();
        return 'main_cell_${row}_$col';
      }
    }
    return null;
  }

  void _onModelChanged() {
    final selection = widget.model.selection;
    final currentSelectionKey =
        '${selection.type}|${selection.zoneId}|${selection.mullionPosition}|'
        '${selection.innerDivisionIndex}|${widget.model.activeSubZone ?? ''}';
    if (currentSelectionKey != _previousSelectionKey) {
      if (selection.type == null) {
        _isLeftDrawerOpen = false;
        _isDrawerOpen = false;
        _isBottomPanelExpanded = false;
      } else {
        // Selecting any drawing element opens its contextual bottom panel.
        _isShutterSelected = false;
        _isBottomPanelExpanded = true;
        _activeBottomTab = 0;
      }
      _previousSelectionKey = currentSelectionKey;
    }

    _syncDrawerGlassFromDrawing();

    if (activeSeriesForSystem?.id != _loadedSeriesId) {
      _loadAvailableProfiles();
    }
    setState(() {});
  }

  /// Synchronise the left glass drawer with the drawing being edited. A
  /// drawing with different glass specifications deliberately keeps the
  /// controls neutral, instead of borrowing an arbitrary selected cell.
  void _syncDrawerGlassFromDrawing() {
    _tempGlassSpec =
        widget.model.getUniformGlassSpecification() ??
            const GlassSpecification();
  }

  // ── تحميل خيارات الستار من قاعدة البيانات ──
  Future<void> _loadShutterOptions() async {
    if (_loadingShutterOptions) return;
    setState(() => _loadingShutterOptions = true);
    try {
      final db = SqlDatabase();
      final dbInstance = await db.db;
      if (dbInstance == null) return;

      // الشفرات (Lames)
      final lames = await dbInstance.query(
        'ShutterComponents',
        where:
        "(LOWER(name) LIKE '%lame%' OR name LIKE '%شريح%' OR LOWER(component_type) LIKE '%lame%' OR LOWER(component_type) LIKE '%blade%') AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'name ASC',
      );

      // السكك (Coulisses)
      final coulisses = await dbInstance.query(
        'ShutterComponents',
        where:
        "(LOWER(name) LIKE '%coulisse%' OR name LIKE '%سك%' OR LOWER(component_type) LIKE '%glissiere%' OR LOWER(component_type) LIKE '%track%' OR LOWER(name) LIKE '%track%') AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'name ASC',
      );

      // الصناديق (Caisson)
      final caissonRes = await dbInstance.query(
        'ShutterComponents',
        where:
        "(LOWER(name) LIKE '%caisson%' OR name LIKE '%صندوق%' OR LOWER(component_type) LIKE '%caisson%' OR LOWER(component_type) LIKE '%box%') AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'name ASC',
      );

      final seriesId = activeSeriesForSystem?.id;
      final designConfig = seriesId == null
          ? null
          : await db.getSeriesDesignConfig(seriesId);
      final shutterRules = seriesId == null
          ? <Map<String, dynamic>>[]
          : await db.getSeriesShutterRules(seriesId);

      List<Map<String, dynamic>> configuredOptions(
          List<Map<String, Object?>> source,
          String role,) {
        final rows = source
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        if (designConfig == null) return rows;
        if (designConfig['supports_shutter'] != 1) {
          return <Map<String, dynamic>>[];
        }
        final candidates = shutterRules.where((rule) {
          if (rule['component_role'] != role) return false;
          final mode = rule['selection_mode']?.toString() ?? 'always';
          final mechanism = widget.model.shutterMechanism;
          if (mode == 'motor' && mechanism != 'محرك') return false;
          if (mode == 'manual' &&
              !(mechanism.contains('مان') || mechanism.contains('منا'))) {
            return false;
          }
          final width = widget.model.width;
          final height = widget.model.height;
          final minW = (rule['min_width_mm'] as num?)?.toDouble();
          final maxW = (rule['max_width_mm'] as num?)?.toDouble();
          final minH = (rule['min_height_mm'] as num?)?.toDouble();
          final maxH = (rule['max_height_mm'] as num?)?.toDouble();
          if (width > 0 &&
              ((minW != null && width < minW) ||
                  (maxW != null && width > maxW))) {
            return false;
          }
          if (height > 0 &&
              ((minH != null && height < minH) ||
                  (maxH != null && height > maxH))) {
            return false;
          }
          return true;
        });
        final ids = candidates
            .map((rule) => (rule['component_id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
        if (ids.isEmpty) return <Map<String, dynamic>>[];
        return rows
            .where((row) => ids.contains((row['id'] as num?)?.toInt()))
            .toList();
      }

      // The shutter is independent from the drawing series.  Do not apply
      // any series-specific profile rules to its catalogue choices.
      final configuredLames = lames
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final configuredCoulisses = coulisses
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final configuredCaissons = caissonRes
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (mounted) {
        setState(() {
          _shutterLamesOptions = configuredLames;
          _shutterCoulisseOptions = configuredCoulisses;
          _shutterCaissonOptions = configuredCaissons;
          _loadingShutterOptions = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingShutterOptions = false);
    }
  }

  @override
  void dispose() {
    _drawingTimer?.cancel();
    _paintbrushTimer?.cancel();
    _catalogReloadDebounce?.cancel();
    _catalogSubscription?.cancel();
    widget.model.removeListener(_onModelChanged);
    _glassScrollController.dispose();
    _leftDrawerScrollController.dispose();
    _leftSashWidthController.dispose();
    _leftSashFocusNode.dispose();
    _positionCtrl.dispose();
    super.dispose();
  }

  Null get items => null;

  void _handleHandleDrag(Offset delta, WindowZone zone) {
    if (zone.openDirection == null && zone.content != ZoneContent.slidingSash) {
      return;
    }
    double dy = delta.dy / (_userScale * widget.model.canvasScale);
    double newRatio = zone.handlePositionRatio ?? 0.5;
    newRatio -= (dy / zone.boundary.height);
    widget.model.updateHandlePosition(zone.id, newRatio.clamp(0.1, 0.9));
  }

  void _handleHingeDrag(Offset delta, WindowZone zone) {
    if (zone.openDirection == null && zone.content != ZoneContent.slidingSash) {
      return;
    }

    // Calculate hingeCount based on sash height
    final double sashHeight = zone.boundary.height;
    int hingeCount = (sashHeight > 2100)
        ? 4
        : (sashHeight > 1000)
        ? 3
        : 2;
    if (zone.glass.structure == GlassStructure.double) {
      hingeCount += 1;
    }

    if (hingeCount < 3) {
      // If 2 hinges, we cannot move anything!
      return;
    }

    double dy = delta.dy / (_userScale * widget.model.canvasScale);
    double newOffset = zone.middleHingeDragOffset;
    newOffset += dy * 200; // Multiply to make it more responsive
    if (newOffset < -150) newOffset = -150;
    if (newOffset > 150) newOffset = 150;
    widget.model.updateHingePosition(zone.id, newOffset);
  }

  bool _isTopZone(WindowZone zone) {
    if (widget.model.zones.isEmpty) return false;
    double minTop = widget.model.zones
        .map((z) => z.boundary.top)
        .reduce(math.min);
    return zone.boundary.top == minTop;
  }

  double getInnerTopY(double x, double t, double topOffset) {
    if (widget.model.archHeight == 0 &&
        widget.model.topSlantLeftY == 0 &&
        widget.model.topSlantRightY == 0) {
      return topOffset + t;
    }
    double factor = 0.0;
    if (widget.model.width > 2 * t) {
      factor = ((x - t) / (widget.model.width - 2 * t)).clamp(0.0, 1.0);
    }
    double yL = topOffset + widget.model.topSlantLeftY + t;
    double yR = topOffset + widget.model.topSlantRightY + t;
    if (widget.model.archHeight > 0) {
      double yC =
          topOffset +
              math.min(
                  widget.model.topSlantLeftY, widget.model.topSlantRightY) -
              (widget.model.archHeight * 2) +
              t;
      return (1.0 - factor) * (1.0 - factor) * yL +
          2.0 * (1.0 - factor) * factor * yC +
          factor * factor * yR;
    } else {
      return yL + factor * (yR - yL);
    }
  }

  double getSashTopY(double x,
      double sashTopFlat,
      double t,
      double topOffset,
      bool isTopBound,) {
    if (!isTopBound) return sashTopFlat;
    double clearance = sashTopFlat - (topOffset + t);
    if (clearance < 0) clearance = 0;
    return getInnerTopY(x, t, topOffset) + clearance;
  }

  void _showMullionResizeDialog(BuildContext context, int section) {
    bool isH = widget.model.selection.isHorizontalMullion!;
    double pos = widget.model.selection.mullionPosition!;
    final t = widget.model.profileThickness;
    double currentValue = isH
        ? (section == 1
        ? (pos - t * 1.5)
        : (widget.model.height - pos - t * 1.5))
        : (section == 1
        ? (pos - t * 1.5)
        : (widget.model.width - pos - t * 1.5));
    final ctrl = TextEditingController(text: currentValue.toInt().toString());
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme
            .of(context)
            .brightness == Brightness.dark;
        String label = isH
            ? (section == 1
            ? 'تعديل الفراغ العلوي (mm)'
            : 'تعديل الفراغ السفلي (mm)')
            : (section == 1
            ? 'تعديل الفراغ الأيسر (mm)'
            : 'تعديل الفراغ الأيمن (mm)');
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: 'البُعد الصافي للفراغ (mm)',
              labelStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.blueGrey,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                final val = double.tryParse(ctrl.text);
                if (val != null && val > 0) {
                  widget.model.resizeMullionDimension(section, val);
                }
                Navigator.pop(context);
              },
              child: const Text(
                'تطبيق القياس الجديد',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _checkAndStartSashDividerDrag(String zoneId,
      bool isRight,
      Rect glassR,
      int innerH,
      int innerV,
      List<double> innerHPos,
      List<double> innerVPos,
      Offset touchScreen,) {
    if (innerH == 0 && innerV == 0) return false;

    // 🟢 تكبير مساحة التقاط اللمس لتسهيل التحديد والتحريك (Hit Slop)
    final double hitRadius = 50.0; // كانت 30.0

    List<double> hPositions = List.from(innerHPos);
    if (hPositions.isEmpty && innerH > 0) {
      double stepY = 1.0 / (innerH + 1);
      for (int i = 1; i <= innerH; i++) {
        hPositions.add(stepY * i);
      }
    }
    List<double> vPositions = List.from(innerVPos);
    if (vPositions.isEmpty && innerV > 0) {
      double stepX = 1.0 / (innerV + 1);
      for (int i = 1; i <= innerV; i++) {
        vPositions.add(stepX * i);
      }
    }

    // Check horizontal dividers
    for (int i = 0; i < hPositions.length; i++) {
      double yVal = glassR.top + glassR.height * hPositions[i];
      final lineStart = _modelToScreen(Offset(glassR.left, yVal));
      final lineEnd = _modelToScreen(Offset(glassR.right, yVal));
      final screenY = lineStart.dy;
      final screenLeft = lineStart.dx;
      final screenRight = lineEnd.dx;

      if ((touchScreen.dy - screenY).abs() < hitRadius &&
          touchScreen.dx >= screenLeft - hitRadius &&
          touchScreen.dx <= screenRight + hitRadius) {
        setState(() {
          _isDraggingSashDivision = true;
          _draggedSashZoneId = zoneId;
          _draggedSashIsRight = isRight;
          _draggedSashIsHorizontal = true;
          _draggedSashIndex = i;
        });
        widget.model.selection = SelectionInfo(
          type: SelectionType.innerDivision,
          zoneId: zoneId,
          isHorizontalInnerDivision: true,
          isRightSashInnerDivision: isRight,
          innerDivisionIndex: i,
        );
        widget.model.showZoneMenu = false;
        widget.model.activeSubZone = null;
        widget.model.refreshUI();
        return true;
      }
    }

    // Check vertical dividers
    for (int i = 0; i < vPositions.length; i++) {
      double xVal = glassR.left + glassR.width * vPositions[i];
      final lineStart = _modelToScreen(Offset(xVal, glassR.top));
      final lineEnd = _modelToScreen(Offset(xVal, glassR.bottom));
      final screenX = lineStart.dx;
      final screenTop = lineStart.dy;
      final screenBottom = lineEnd.dy;

      if ((touchScreen.dx - screenX).abs() < hitRadius &&
          touchScreen.dy >= screenTop - hitRadius &&
          touchScreen.dy <= screenBottom + hitRadius) {
        setState(() {
          _isDraggingSashDivision = true;
          _draggedSashZoneId = zoneId;
          _draggedSashIsRight = isRight;
          _draggedSashIsHorizontal = false;
          _draggedSashIndex = i;
        });
        widget.model.selection = SelectionInfo(
          type: SelectionType.innerDivision,
          zoneId: zoneId,
          isHorizontalInnerDivision: false,
          isRightSashInnerDivision: isRight,
          innerDivisionIndex: i,
        );
        widget.model.showZoneMenu = false;
        widget.model.activeSubZone = null;
        widget.model.refreshUI();
        return true;
      }
    }

    return false;
  }

  bool _checkAndStartGlassDecorDrag(String zoneId,
      Rect glassR,
      GlassSpecification spec,
      Offset touchScreen,) {
    if (spec.structure != GlassStructure.double) return false;
    if (spec.decorH == 0 && spec.decorV == 0) return false;

    final double hitRadius = 50.0;

    List<double> hPositions = List.from(spec.decorHPositions);
    if (hPositions.isEmpty && spec.decorH > 0) {
      double stepY = 1.0 / (spec.decorH + 1);
      for (int i = 1; i <= spec.decorH; i++) {
        hPositions.add(stepY * i);
      }
    }
    List<double> vPositions = List.from(spec.decorVPositions);
    if (vPositions.isEmpty && spec.decorV > 0) {
      double stepX = 1.0 / (spec.decorV + 1);
      for (int i = 1; i <= spec.decorV; i++) {
        vPositions.add(stepX * i);
      }
    }

    // Check horizontal dividers
    for (int i = 0; i < hPositions.length; i++) {
      double yVal = glassR.top + glassR.height * hPositions[i];
      final lineStart = _modelToScreen(Offset(glassR.left, yVal));
      final lineEnd = _modelToScreen(Offset(glassR.right, yVal));
      final screenY = lineStart.dy;
      final screenLeft = lineStart.dx;
      final screenRight = lineEnd.dx;

      if ((touchScreen.dy - screenY).abs() < hitRadius &&
          touchScreen.dx >= screenLeft - hitRadius &&
          touchScreen.dx <= screenRight + hitRadius) {
        setState(() {
          _isDraggingDecor = true;
          _draggedDecorZoneId = zoneId;
          _draggedDecorIsHorizontal = true;
          _draggedDecorIndex = i;
        });
        widget.model.showZoneMenu = false;
        widget.model.activeSubZone = null;
        widget.model.refreshUI();
        return true;
      }
    }

    // Check vertical dividers
    for (int i = 0; i < vPositions.length; i++) {
      double xVal = glassR.left + glassR.width * vPositions[i];
      final lineStart = _modelToScreen(Offset(xVal, glassR.top));
      final lineEnd = _modelToScreen(Offset(xVal, glassR.bottom));
      final screenX = lineStart.dx;
      final screenTop = lineStart.dy;
      final screenBottom = lineEnd.dy;

      if ((touchScreen.dx - screenX).abs() < hitRadius &&
          touchScreen.dy >= screenTop - hitRadius &&
          touchScreen.dy <= screenBottom + hitRadius) {
        setState(() {
          _isDraggingDecor = true;
          _draggedDecorZoneId = zoneId;
          _draggedDecorIsHorizontal = false;
          _draggedDecorIndex = i;
        });
        widget.model.showZoneMenu = false;
        widget.model.activeSubZone = null;
        widget.model.refreshUI();
        return true;
      }
    }

    return false;
  }

  void _startDrawingTimer() {
    _drawingTimer?.cancel();
    widget.model.setDrawingMode(true);
    _drawingTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        widget.model.setDrawingMode(false);
      }
    });
  }

  void _stopDrawingTimer() {
    _drawingTimer?.cancel();
    widget.model.setDrawingMode(false);
  }

  @override
  void initState() {
    super.initState();
    _positionCtrl = TextEditingController(text: widget.model.position ?? '');
    widget.model.loadCatalogData(widget.systemMode);
    widget.model.addListener(_onModelChanged);
    _syncDrawerGlassFromDrawing();
    if (activeSeriesForSystem != null) {
      _loadAvailableProfiles();
    }
    _loadShutterOptions(); // Preload shutter options from database
    _catalogSubscription = CloudSyncService().dbUpdateStream.listen((update) {
      if (update != 'catalog_changed' &&
          update != 'catalog_downloaded' &&
          update != 'cloud_restored') {
        return;
      }
      _catalogReloadDebounce?.cancel();
      _catalogReloadDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        unawaited(widget.model.loadCatalogData(widget.systemMode));
        _loadedSeriesId = null;
        unawaited(_loadAvailableProfiles());
        _loadShutterOptions();
      });
    });
    SharedPreferences.getInstance().then((prefs) {
      final name = prefs.getString('workshop_name');
      if (name != null && name
          .trim()
          .isNotEmpty) {
        widget.model.workshopName = name;
        widget.model.refreshUI();
      }
    });
    // Activate drawing mode for 10 seconds when entering the screen
    widget.model.setDrawingMode(false);
  }

  Offset _getModelPos(Offset screenPos) {
    final totalScale = widget.model.canvasScale * _userScale;
    return Offset(
      (screenPos.dx - widget.model.canvasDx - _userPan.dx) / totalScale,
      (screenPos.dy - widget.model.canvasDy - _userPan.dy) / totalScale,
    );
  }

  Offset _modelToScreen(Offset modelPosition) {
    final totalScale = widget.model.canvasScale * _userScale;
    return Offset(
      widget.model.canvasDx + _userPan.dx + modelPosition.dx * totalScale,
      widget.model.canvasDy + _userPan.dy + modelPosition.dy * totalScale,
    );
  }

  void _changeDrawingZoom(double factor, Offset focalPoint) {
    final double nextScale = (_userScale * factor).clamp(
      _minUserScale,
      _maxUserScale,
    );
    if (nextScale == _userScale) return;

    setState(() {
      final scaleRatio = nextScale / _userScale;
      // canvasDx/canvasDy are applied before the user zoom.  Keeping them in
      // this equation makes the focal point truly stationary instead of
      // pulling the drawing towards the top-left on every zoom step.
      final canvasOrigin = Offset(widget.model.canvasDx, widget.model.canvasDy);
      _userPan = focalPoint -
          canvasOrigin -
          (focalPoint - canvasOrigin - _userPan) * scaleRatio;
      _userScale = nextScale;
    });
  }

  void _handleDrawingPointerSignal(PointerSignalEvent event) {
    if (!_isWindowsDesktop || event is! PointerScrollEvent) return;
    final verticalDelta = event.scrollDelta.dy;
    if (verticalDelta == 0) return;

    // Keep the drawing centred in its own viewport, independent of where the
    // mouse happens to be on the page.
    _changeDrawingZoom(
      verticalDelta < 0 ? _zoomStep : 1 / _zoomStep,
      _drawingViewportCenter(),
    );
  }

  void _resetDrawingZoom() {
    setState(() {
      _userScale = 1.0;
      _userPan = Offset.zero;
    });
    // The drawing stays where it was created until the user explicitly asks
    // to centre it using this control.
    widget.model.centerDrawingOnCanvas();
  }

  Offset _drawingViewportCenter() {
    final size = widget.model.lastLayoutSize;
    if (size == null) return Offset.zero;
    return Offset(size.width / 2, size.height / 2);
  }

  Rect _outerRectForFrame(WindowZone zone) {
    final thickness = widget.model.profileThickness;
    return Rect.fromLTRB(
      zone.boundary.left - thickness,
      zone.boundary.top - thickness,
      zone.boundary.right + thickness,
      zone.boundary.bottom + thickness,
    );
  }

  WindowZone? _frameAtBorder(Offset modelPosition) {
    if (widget.model.zones.length < 2) return null;
    final thickness = widget.model.profileThickness;
    for (final zone in widget.model.zones.reversed) {
      final outer = _outerRectForFrame(zone);
      final inner = outer.deflate(thickness * 0.72);
      if (outer.contains(modelPosition) && !inner.contains(modelPosition)) {
        return zone;
      }
    }
    return null;
  }

  _FrameResizeHandle? _frameResizeHandleAt(Offset screenPosition) {
    final frameId = widget.model.selection.type == SelectionType.frame
        ? widget.model.selection.zoneId
        : null;
    if (frameId == null) return null;
    WindowZone? zone;
    for (final candidate in widget.model.zones) {
      if (candidate.id == frameId) {
        zone = candidate;
        break;
      }
    }
    if (zone == null) return null;

    final outer = _outerRectForFrame(zone);
    final handles = <_FrameResizeHandle, Offset>{
      _FrameResizeHandle.topLeft: outer.topLeft,
      _FrameResizeHandle.top: Offset(outer.center.dx, outer.top),
      _FrameResizeHandle.topRight: outer.topRight,
      _FrameResizeHandle.right: Offset(outer.right, outer.center.dy),
      _FrameResizeHandle.bottomRight: outer.bottomRight,
      _FrameResizeHandle.bottom: Offset(outer.center.dx, outer.bottom),
      _FrameResizeHandle.bottomLeft: outer.bottomLeft,
      _FrameResizeHandle.left: Offset(outer.left, outer.center.dy),
    };

    _FrameResizeHandle? closest;
    double closestDistance = 24.0;
    for (final entry in handles.entries) {
      final distance = (_modelToScreen(entry.value) - screenPosition).distance;
      if (distance <= closestDistance) {
        closest = entry.key;
        closestDistance = distance;
      }
    }
    return closest;
  }

  Rect? _dimensionTextBounds(String text, Rect bounds, {bool vertical = false}) {
    final crossAxis = vertical ? bounds.width : bounds.height;
    final mainAxis = vertical ? bounds.height : bounds.width;
    if (crossAxis < 12 || mainAxis < 35) return null;

    double fontSize = math.min(22.0, math.max(10.0, crossAxis * 0.52));
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w400),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width <= mainAxis - 8 || fontSize <= 8) break;
      fontSize -= 1.0;
    }
    if (painter.width > mainAxis - 4) return null;

    return vertical
        ? Rect.fromCenter(
            center: bounds.center,
            width: painter.height + 6,
            height: painter.width + 8,
          )
        : Rect.fromCenter(
            center: bounds.center,
            width: painter.width + 8,
            height: painter.height + 6,
          );
  }

  /// Hit-test only the visible number written in the selected frame profile.
  /// The remaining profile area stays available for selecting the frame.
  InnerDimensionHit? _frameProfileDimensionHit(Offset modelPosition) {
    if (widget.model.zones.length < 2) return null;
    final thickness = widget.model.profileThickness;
    final showWidthInside = widget.model.getVerticalFrameJoints().isEmpty;
    final showHeightInside = widget.model.getHorizontalFrameJoints().isEmpty;
    for (final zone in widget.model.zones.reversed) {
      final outer = _outerRectForFrame(zone);
      if (showWidthInside) {
        final widthBounds = Rect.fromLTWH(
          outer.left + 2,
          outer.top + 1,
          math.max(0.0, outer.width - 4),
          math.max(0.0, thickness - 2),
        );
        final widthText = _dimensionTextBounds(
          '${outer.width.toInt()}',
          widthBounds,
        );
        if (widthText?.contains(modelPosition) == true) {
          return InnerDimensionHit(zone.id, true);
        }
      }

      if (showHeightInside) {
        final heightBounds = Rect.fromLTWH(
          outer.left + 1,
          outer.top + 2,
          math.max(0.0, thickness - 2),
          math.max(0.0, outer.height - 4),
        );
        final heightText = _dimensionTextBounds(
          '${outer.height.toInt()}',
          heightBounds,
          vertical: true,
        );
        if (heightText?.contains(modelPosition) == true) {
          return InnerDimensionHit(zone.id, false);
        }
      }
    }
    return null;
  }

  void _toggleDrawingInteractionMode() {
    if (widget.model.isDrawingMode) {
      _stopDrawingTimer();
    } else {
      _startDrawingTimer();
    }
    setState(() {});
  }

  List<Widget> _buildWindowsAppBarDrawingControls(BuildContext context) {
    final lang = Provider
        .of<AppSettingsProvider>(context)
        .language;
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    final foreground = isDark ? Colors.blue.shade200 : Colors.blue.shade900;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: VisualDensity.compact,
    );

    IconButton iconButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) {
      return IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: foreground,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
    }

    return [
      const SizedBox(width: 8),
      TextButton.icon(
        style: buttonStyle,
        onPressed: () => _showResizeDialog(context, focusWidth: true),
        icon: const Icon(Icons.straighten_rounded, size: 18),
        label: Text(
          '${widget.model.width.toInt()} × ${widget.model.height.toInt()}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      TextButton.icon(
        style: buttonStyle,
        onPressed: _toggleDrawingInteractionMode,
        icon: Icon(
          widget.model.isDrawingMode
              ? Icons.draw_rounded
              : Icons.pan_tool_alt_rounded,
          size: 18,
        ),
        label: Text(
          widget.model.isDrawingMode
              ? Localization.translate('وضع الرسم', lang)
              : Localization.translate('وضع التحريك', lang),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      iconButton(
        icon: Icons.center_focus_strong_outlined,
        tooltip: Localization.translate('توسيط الرسم', lang),
        onPressed: _resetDrawingZoom,
      ),
      iconButton(
        icon: Icons.remove,
        tooltip: Localization.translate('تصغير الرسم', lang),
        onPressed: () =>
            _changeDrawingZoom(1 / _zoomStep, _drawingViewportCenter()),
      ),
      iconButton(
        icon: Icons.add,
        tooltip: Localization.translate('تكبير الرسم', lang),
        onPressed: () =>
            _changeDrawingZoom(_zoomStep, _drawingViewportCenter()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final hasSelection = widget.model.selectedZone != null;
        final isMullionSelected =
            widget.model.selection.type == SelectionType.mullion;
        final isInnerDivisionSelected =
            widget.model.selection.type == SelectionType.innerDivision;

        return Scaffold(
          backgroundColor: Theme
              .of(context)
              .brightness == Brightness.dark
              ? const Color(0xFF1E1E2C)
              : const Color(0xFFE8EAF6),
          appBar: _buildAppBar(context),
          body: Stack(
            children: [
              Column(
                children: [
                  if (isInnerDivisionSelected)
                    _buildInnerDivisionToolbar(context)
                  else
                    ...[
                      if (!_isWindowsDesktop && !isMullionSelected)
                        _buildSplitToolbar(context, hasSelection),
                      if (isMullionSelected) _buildMullionToolbar(context),
                    ],

                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        widget.model.updateLayoutMetrics(
                          Size(constraints.maxWidth, constraints.maxHeight),
                        );
                        return Stack(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) {
                                final modelPos = _getModelPos(
                                  details.localPosition,
                                );

                                // --- Individual frame dimension tap (coupled windows) ---
                                // First check the number painted directly in
                                // a frame profile.  This is intentionally
                                // narrower than the surrounding profile.
                                InnerDimensionHit? individualTap =
                                    _frameProfileDimensionHit(modelPos);
                                if (widget.model.zones.length > 1) {
                                  final double scW =
                                      widget.model.sideCoverWidth;
                                  double offsetDistTop = 60.0;
                                  if (widget.model.hasShutter)
                                    offsetDistTop += 20.0;
                                  if (widget.model.hasSideCovers &&
                                      !widget.model.removedShutterSides
                                          .contains('top')) {
                                    offsetDistTop += scW + 15.0;
                                  }
                                  double offsetDistRight = 50.0;
                                  if (widget.model.hasSideCovers &&
                                      !widget.model.removedShutterSides
                                          .contains('right')) {
                                    offsetDistRight += scW + 15.0;
                                  }
                                  double offsetDistBottom = 50.0;
                                  if (widget.model.hasSideCovers &&
                                      widget.model.hasBottomFrame &&
                                      !widget.model.removedShutterSides
                                          .contains('bottom')) {
                                    offsetDistBottom += scW + 15.0;
                                  }
                                  final bool isSlantedOrArched =
                                      widget.model.archHeight > 0 ||
                                          widget.model.topSlantLeftY != 0 ||
                                          widget.model.topSlantRightY != 0 ||
                                          widget.model.bottomSlantLeftY != 0 ||
                                          widget.model.bottomSlantRightY != 0;

                                  // Layer-1 width tap
                                  final vJoints = widget.model
                                      .getVerticalFrameJoints();
                                  if (individualTap == null &&
                                      vJoints.isNotEmpty) {
                                    final xCoords = [
                                      0.0,
                                      ...vJoints,
                                      widget.model.width,
                                    ];
                                    for (
                                    int i = 0;
                                    i < xCoords.length - 1;
                                    i++
                                    ) {
                                    double xCenter =
                                        (xCoords[i] + xCoords[i + 1]) / 2;
                                    double wY;
                                    if (isSlantedOrArched) {
                                      double maxBottomY = math.max(
                                        widget.model.bottomSlantLeftY,
                                        widget.model.bottomSlantRightY,
                                      );
                                      wY =
                                          widget.model.height +
                                              maxBottomY +
                                              offsetDistBottom;
                                    } else {
                                      wY = -offsetDistTop;
                                      if (widget.model.hasShutter &&
                                          widget.model.isCaissonTunnel) {
                                        wY -= widget.model.shutterBoxHeight;
                                      }
                                    }
                                    // Individual width labels are drawn one
                                    // layer below the total width label.
                                    if ((modelPos.dx - xCenter).abs() < 85.0 &&
                                        (modelPos.dy - (wY + 50.0)).abs() <
                                            28.0) {
                                      final targetZone = widget.model.zones
                                          .reduce(
                                            (a, b) =>
                                        (a.boundary.center.dx - xCenter)
                                            .abs() <
                                            (b.boundary.center.dx -
                                                xCenter)
                                                .abs()
                                            ? a
                                            : b,
                                      );
                                      individualTap = InnerDimensionHit(
                                        targetZone.id,
                                        true,
                                      );
                                      break;
                                    }
                                  }
                                  }
                                  // Layer-1 height tap
                                  if (individualTap == null) {
                                    final hJoints = widget.model
                                        .getHorizontalFrameJoints();
                                    if (hJoints.isNotEmpty) {
                                      final yCoords = [
                                        0.0,
                                        ...hJoints,
                                        widget.model.height,
                                      ];
                                      for (
                                      int j = 0;
                                      j < yCoords.length - 1;
                                      j++
                                      ) {
                                      double yCenter =
                                          (yCoords[j] + yCoords[j + 1]) / 2;
                                      final individualX =
                                          widget.model.width +
                                              offsetDistRight +
                                              50.0;
                                      if ((modelPos.dy - yCenter).abs() <
                                          85.0) {
                                        if ((modelPos.dx - individualX).abs() <
                                            28.0) {
                                          final rowZones = widget.model.zones
                                              .where(
                                                (z) =>
                                            z.boundary.top <=
                                                yCenter + 5 &&
                                                z.boundary.bottom >=
                                                    yCenter - 5,
                                          )
                                              .toList();
                                          final targetZone =
                                          (rowZones.isEmpty
                                              ? widget.model.zones
                                              : rowZones)
                                              .reduce(
                                                (a, b) =>
                                            a.boundary.right >
                                                b.boundary.right
                                                ? a
                                                : b,
                                          );
                                          individualTap = InnerDimensionHit(
                                            targetZone.id,
                                            false,
                                          );
                                          break;
                                        }
                                      }
                                    }
                                    }
                                  }
                                }
                                if (individualTap != null) {
                                  _showFrameResizeDialog(
                                    context,
                                    individualTap,
                                  );
                                  return;
                                }
                                // --- end individual frame tap ---

                                if (_paintbrushSecondsLeft > 0 ||
                                    _isLeftDrawerOpen) {
                                  // A prepared zone type has priority over
                                  // the glass brush. This makes a choice such
                                  // as "double sash" apply to the frame that
                                  // is clicked next.
                                  if (_activePaintZoneContent != null) {
                                    WindowZone? tappedZ;
                                    for (final zone in widget.model.zones) {
                                      if (zone.boundary.contains(modelPos)) {
                                        tappedZ = zone;
                                        break;
                                      }
                                    }
                                    if (tappedZ != null) {
                                      widget.model.paintZoneContent(
                                        tappedZ.id,
                                        _activePaintZoneContent!,
                                        slidingSashesCount:
                                            _activePaintSlidingSashesCount,
                                      );
                                      setState(() {
                                        _paintbrushSecondsLeft = 10;
                                      });
                                      return;
                                    }
                                  }
                                  final specToApply =
                                      _activePaintGlassSpec ??
                                          (widget.model.selectedZone != null
                                              ? widget.model.selectedZone!
                                              .getGlassForCell(
                                            widget.model.activeSubZone,
                                          )
                                              : _tempGlassSpec);
                                  if (specToApply != null) {
                                    WindowZone? tappedZ;
                                    for (var z in widget.model.zones) {
                                      if (z.boundary.contains(modelPos)) {
                                        tappedZ = z;
                                        break;
                                      }
                                    }
                                    if (tappedZ != null) {
                                      String? tappedCellId;
                                      bool isDouble =
                                          tappedZ.content ==
                                              ZoneContent.doubleSash;
                                      bool isSingle =
                                          tappedZ.content ==
                                              ZoneContent.singleSash;
                                      bool isSliding =
                                          tappedZ.content ==
                                              ZoneContent.slidingSash;
                                      if (isDouble || isSingle || isSliding) {
                                        if (isSliding) {
                                          final count =
                                              tappedZ.slidingSashesCount;
                                          double chicaneT = 45.0;
                                          final series =
                                              widget
                                                  .model
                                                  .activeSlidingSeries ??
                                                  widget.model.activeSeries;
                                          if (series != null) {
                                            for (var sec in series.sections) {
                                              final secType = sec.type
                                                  .toLowerCase();
                                              if (secType == 'chicane' ||
                                                  secType == 'sash_central' ||
                                                  secType == 'central' ||
                                                  secType == 'centrale') {
                                                if (sec.visibleWidth > 0) {
                                                  chicaneT = sec.visibleWidth;
                                                } else if (sec.thickness > 0)
                                                  chicaneT = sec.thickness;
                                              }
                                            }
                                          }
                                          final double sashWidth =
                                              (tappedZ.boundary.width +
                                                  (count - 1) * chicaneT) /
                                                  count;

                                          List<int> tracks;
                                          if (count == 2) {
                                            tracks =
                                            (tappedZ.openDirection ==
                                                OpenDirection.left)
                                                ? [1, 0]
                                                : [0, 1];
                                          } else if (count == 3) {
                                            tracks = [0, 1, 0];
                                          } else if (count == 4) {
                                            tracks = [0, 1, 1, 0];
                                          } else {
                                            tracks = List.generate(
                                              count,
                                                  (i) => i % 2,
                                            );
                                          }

                                          int selectedSashIndex = -1;
                                          for (int tg = 1; tg >= 0; tg--) {
                                            for (int i = 0; i < count; i++) {
                                              if (tracks[i] == tg) {
                                                double left =
                                                    tappedZ.boundary.left +
                                                        i * (sashWidth -
                                                            chicaneT);
                                                Rect sashRect = Rect.fromLTRB(
                                                  left,
                                                  tappedZ.boundary.top,
                                                  left + sashWidth,
                                                  tappedZ.boundary.bottom,
                                                );
                                                if (sashRect.contains(
                                                  modelPos,
                                                )) {
                                                  selectedSashIndex = i;
                                                  break;
                                                }
                                              }
                                            }
                                            if (selectedSashIndex != -1) break;
                                          }

                                          if (selectedSashIndex == -1) {
                                            double tX =
                                                (modelPos.dx -
                                                    tappedZ.boundary.left) /
                                                    tappedZ.boundary.width;
                                            selectedSashIndex = (tX * count)
                                                .floor()
                                                .clamp(0, count - 1);
                                          }

                                          tappedCellId =
                                          'main_cell_0_$selectedSashIndex';
                                        } else {
                                          double splitX =
                                              tappedZ.boundary.left +
                                                  tappedZ.boundary.width *
                                                      tappedZ.doubleSashRatio;
                                          bool isRight =
                                              isDouble &&
                                                  (modelPos.dx > splitX);
                                          Rect sashR = tappedZ.boundary;
                                          if (isDouble) {
                                            final sep = 4.0;
                                            sashR = isRight
                                                ? Rect.fromLTRB(
                                              splitX + sep / 2,
                                              tappedZ.boundary.top,
                                              tappedZ.boundary.right,
                                              tappedZ.boundary.bottom,
                                            )
                                                : Rect.fromLTRB(
                                              tappedZ.boundary.left,
                                              tappedZ.boundary.top,
                                              splitX - sep / 2,
                                              tappedZ.boundary.bottom,
                                            );
                                          }
                                          final sashT =
                                              tappedZ.sashThickness ??
                                                  widget.model
                                                      .getSectionThickness(
                                                    'sash',
                                                    fallback: 45.0,
                                                  );
                                          final glassR = sashR.deflate(sashT);
                                          if (glassR.contains(modelPos)) {
                                            int currentInnerH = isRight
                                                ? tappedZ.rightInnerH
                                                : tappedZ.innerH;
                                            int currentInnerV = isRight
                                                ? tappedZ.rightInnerV
                                                : tappedZ.innerV;
                                            double cellW =
                                                glassR.width /
                                                    (currentInnerV + 1);
                                            double cellH =
                                                glassR.height /
                                                    (currentInnerH + 1);
                                            final clampedX = modelPos.dx.clamp(
                                              glassR.left + 0.1,
                                              glassR.right - 0.1,
                                            );
                                            final clampedY = modelPos.dy.clamp(
                                              glassR.top + 0.1,
                                              glassR.bottom - 0.1,
                                            );
                                            int col =
                                            ((clampedX - glassR.left) /
                                                cellW)
                                                .clamp(0, currentInnerV)
                                                .toInt();
                                            int row =
                                            ((clampedY - glassR.top) /
                                                cellH)
                                                .clamp(0, currentInnerH)
                                                .toInt();
                                            String sidePrefix = isDouble
                                                ? (isRight ? 'right' : 'left')
                                                : 'main';
                                            tappedCellId =
                                            '${sidePrefix}_cell_${row}_$col';
                                          } else {
                                            tappedCellId = null;
                                          }
                                        }
                                      } else {
                                        // Non-sash zone (fixed glass, etc.)
                                        final glassR = tappedZ.boundary;
                                        int currentInnerH = tappedZ.innerH;
                                        int currentInnerV = tappedZ.innerV;
                                        double cellW =
                                            glassR.width / (currentInnerV + 1);
                                        double cellH =
                                            glassR.height / (currentInnerH + 1);
                                        final clampedX = modelPos.dx.clamp(
                                          glassR.left + 0.1,
                                          glassR.right - 0.1,
                                        );
                                        final clampedY = modelPos.dy.clamp(
                                          glassR.top + 0.1,
                                          glassR.bottom - 0.1,
                                        );
                                        int col =
                                        ((clampedX - glassR.left) / cellW)
                                            .clamp(0, currentInnerV)
                                            .toInt();
                                        int row =
                                        ((clampedY - glassR.top) / cellH)
                                            .clamp(0, currentInnerH)
                                            .toInt();
                                        tappedCellId = 'main_cell_${row}_$col';
                                      }
                                      widget.model.paintZoneOrCellSpec(
                                        tappedZ.id,
                                        spec: specToApply,
                                        cellId: tappedCellId,
                                      );
                                      // إعادة المؤقت عند كل ضغطة ناجحة
                                      setState(() {
                                        _paintbrushSecondsLeft = 10;
                                      });
                                      return;
                                    }
                                  } else if (_activePaintFinish != null) {
                                    WindowZone? tappedZ;
                                    for (var z in widget.model.zones) {
                                      if (z.boundary.contains(modelPos)) {
                                        tappedZ = z;
                                        break;
                                      }
                                    }
                                    if (tappedZ != null) {
                                      String? tappedCellId;
                                      bool isDouble =
                                          tappedZ.content ==
                                              ZoneContent.doubleSash;
                                      bool isSingle =
                                          tappedZ.content ==
                                              ZoneContent.singleSash;
                                      bool isSliding =
                                          tappedZ.content ==
                                              ZoneContent.slidingSash;
                                      if (isDouble || isSingle || isSliding) {
                                        double splitX =
                                            tappedZ.boundary.left +
                                                tappedZ.boundary.width *
                                                    tappedZ.doubleSashRatio;
                                        bool isRight =
                                            isDouble && (modelPos.dx > splitX);
                                        Rect sashR = tappedZ.boundary;
                                        if (isDouble) {
                                          final sep = 4.0;
                                          sashR = isRight
                                              ? Rect.fromLTRB(
                                            splitX + sep / 2,
                                            tappedZ.boundary.top,
                                            tappedZ.boundary.right,
                                            tappedZ.boundary.bottom,
                                          )
                                              : Rect.fromLTRB(
                                            tappedZ.boundary.left,
                                            tappedZ.boundary.top,
                                            splitX - sep / 2,
                                            tappedZ.boundary.bottom,
                                          );
                                        }
                                        final sashT =
                                            tappedZ.sashThickness ??
                                                widget.model
                                                    .getSectionThickness(
                                                  'sash',
                                                  fallback: 45.0,
                                                );
                                        final glassR = sashR.deflate(sashT);
                                        if (glassR.contains(modelPos)) {
                                          int currentInnerH = isRight
                                              ? tappedZ.rightInnerH
                                              : tappedZ.innerH;
                                          int currentInnerV = isRight
                                              ? tappedZ.rightInnerV
                                              : tappedZ.innerV;
                                          double cellW =
                                              glassR.width /
                                                  (currentInnerV + 1);
                                          double cellH =
                                              glassR.height /
                                                  (currentInnerH + 1);
                                          int col =
                                          ((modelPos.dx - glassR.left) /
                                              cellW)
                                              .clamp(0, currentInnerV)
                                              .toInt();
                                          int row =
                                          ((modelPos.dy - glassR.top) /
                                              cellH)
                                              .clamp(0, currentInnerH)
                                              .toInt();
                                          String sidePrefix = isDouble
                                              ? (isRight ? 'right' : 'left')
                                              : 'main';
                                          tappedCellId =
                                          '${sidePrefix}_cell_${row}_$col';
                                        }
                                      } else {
                                        // Non-sash zone (fixed glass, etc.)
                                        final glassR = tappedZ.boundary;
                                        if (glassR.contains(modelPos)) {
                                          int currentInnerH = tappedZ.innerH;
                                          int currentInnerV = tappedZ.innerV;
                                          double cellW =
                                              glassR.width /
                                                  (currentInnerV + 1);
                                          double cellH =
                                              glassR.height /
                                                  (currentInnerH + 1);
                                          int col =
                                          ((modelPos.dx - glassR.left) /
                                              cellW)
                                              .clamp(0, currentInnerV)
                                              .toInt();
                                          int row =
                                          ((modelPos.dy - glassR.top) /
                                              cellH)
                                              .clamp(0, currentInnerH)
                                              .toInt();
                                          tappedCellId =
                                          'main_cell_${row}_$col';
                                        }
                                      }
                                      widget.model.paintZoneOrCell(
                                        tappedZ.id,
                                        finish: _activePaintFinish!,
                                        structure: _activePaintStructure!,
                                        cellId: tappedCellId,
                                      );
                                      return;
                                    }
                                  } else if (_activePaintZoneContent != null) {
                                    WindowZone? tappedZ;
                                    for (var z in widget.model.zones) {
                                      if (z.boundary.contains(modelPos)) {
                                        tappedZ = z;
                                        break;
                                      }
                                    }
                                    if (tappedZ != null) {
                                      widget.model.paintZoneContent(
                                        tappedZ.id,
                                        _activePaintZoneContent!,
                                        slidingSashesCount:
                                        _activePaintSlidingSashesCount,
                                      );
                                      return;
                                    }
                                  } else if (_activePaintCellSash) {
                                    WindowZone? tappedZ;
                                    for (var z in widget.model.zones) {
                                      if (z.boundary.contains(modelPos)) {
                                        tappedZ = z;
                                        break;
                                      }
                                    }
                                    if (tappedZ != null) {
                                      final cellId = _getTappedCellId(
                                        tappedZ,
                                        modelPos,
                                      );
                                      if (cellId != null) {
                                        widget.model.paintCellSash(
                                          tappedZ.id,
                                          cellId,
                                          true,
                                        );
                                      }
                                      return;
                                    }
                                  } else if (_activePaintCellPanel) {
                                    WindowZone? tappedZ;
                                    for (var z in widget.model.zones) {
                                      if (z.boundary.contains(modelPos)) {
                                        tappedZ = z;
                                        break;
                                      }
                                    }
                                    if (tappedZ != null) {
                                      final cellId = _getTappedCellId(
                                        tappedZ,
                                        modelPos,
                                      );
                                      if (cellId != null) {
                                        widget.model.paintCellPanel(
                                          tappedZ.id,
                                          cellId,
                                          true,
                                        );
                                      }
                                      return;
                                    }
                                  }
                                }

                                final outerTap = widget.model
                                    .checkOuterDimensionTap(modelPos);
                                // The compact number inside each outer frame
                                // has priority over the general dimension
                                // areas, so only the visible number opens its
                                // own edit dialog.
                                final innerTap =
                                    _frameProfileDimensionHit(modelPos) ??
                                    widget.model.checkInnerDimensionTap(
                                      modelPos,
                                    );
                                final mullionDimTap = widget.model
                                    .checkMullionDimensionTap(modelPos);

                                bool tappedZone = false;
                                for (var z in widget.model.zones) {
                                  if (z.boundary.contains(modelPos)) {
                                    tappedZone = true;
                                    break;
                                  }
                                }

                                bool tappedMullion = false;
                                bool? tappedMullionIsHorizontal;
                                double? tappedMullionPosition;
                                double nearestMullionDistance = double.infinity;
                                double hitSlop = 40.0;
                                final mullionT = widget.model.mullionThickness;
                                for (
                                int i = 0;
                                i < widget.model.zones.length;
                                i++
                                ) {
                                  for (
                                  int j = i + 1;
                                  j < widget.model.zones.length;
                                  j++
                                  ) {
                                    final z1 = widget.model.zones[i].boundary;
                                    final z2 = widget.model.zones[j].boundary;
                                    if ((z1.bottom - z2.top).abs() <=
                                        mullionT + 2 ||
                                        (z2.bottom - z1.top).abs() <=
                                            mullionT + 2) {
                                      double yCenter = (z1.bottom + z2.top) / 2;
                                      if ((z2.bottom - z1.top).abs() <=
                                          mullionT + 2) {
                                        yCenter = (z2.bottom + z1.top) / 2;
                                      }
                                      double overlapLeft = math.max(
                                        z1.left,
                                        z2.left,
                                      );
                                      double overlapRight = math.min(
                                        z1.right,
                                        z2.right,
                                      );
                                      if (overlapLeft < overlapRight &&
                                          modelPos.dx >= overlapLeft &&
                                          modelPos.dx <= overlapRight &&
                                          (modelPos.dy - yCenter).abs() <
                                              hitSlop) {
                                        final distance = (modelPos.dy - yCenter)
                                            .abs();
                                        if (distance < nearestMullionDistance) {
                                          tappedMullion = true;
                                          tappedMullionIsHorizontal = true;
                                          tappedMullionPosition = yCenter;
                                          nearestMullionDistance = distance;
                                        }
                                      }
                                    }
                                    if ((z1.right - z2.left).abs() <=
                                        mullionT + 2 ||
                                        (z2.right - z1.left).abs() <=
                                            mullionT + 2) {
                                      double xCenter = (z1.right + z2.left) / 2;
                                      if ((z2.right - z1.left).abs() <=
                                          mullionT + 2) {
                                        xCenter = (z2.right + z1.left) / 2;
                                      }
                                      double overlapTop = math.max(
                                        z1.top,
                                        z2.top,
                                      );
                                      double overlapBottom = math.min(
                                        z1.bottom,
                                        z2.bottom,
                                      );
                                      if (overlapTop < overlapBottom &&
                                          modelPos.dy >= overlapTop &&
                                          modelPos.dy <= overlapBottom &&
                                          (modelPos.dx - xCenter).abs() <
                                              hitSlop) {
                                        final distance = (modelPos.dx - xCenter)
                                            .abs();
                                        if (distance < nearestMullionDistance) {
                                          tappedMullion = true;
                                          tappedMullionIsHorizontal = false;
                                          tappedMullionPosition = xCenter;
                                          nearestMullionDistance = distance;
                                        }
                                      }
                                    }
                                  }
                                }

                                final now = DateTime.now();
                                bool isDoubleTap = false;
                                if (_lastTapTime != null &&
                                    now.difference(_lastTapTime!) <
                                        const Duration(milliseconds: 300)) {
                                  if (_lastTapPosition != null &&
                                      (details.localPosition -
                                          _lastTapPosition!)
                                          .distance <
                                          30.0) {
                                    isDoubleTap = true;
                                  }
                                }
                                _lastTapTime = now;
                                _lastTapPosition = details.localPosition;

                                if (!tappedZone &&
                                    !tappedMullion &&
                                    outerTap == DimensionTap.none &&
                                    innerTap == null &&
                                    mullionDimTap == null) {
                                  if (_isDrawerOpen || _isLeftDrawerOpen) {
                                    setState(() {
                                      _isDrawerOpen = false;
                                      _isLeftDrawerOpen = false;
                                    });
                                    return;
                                  }
                                }

                                if (outerTap != DimensionTap.none) {
                                  _showResizeDialog(
                                    context,
                                    focusWidth: outerTap == DimensionTap.width,
                                  );
                                  return;
                                }
                                if (innerTap != null) {
                                  _showInnerResizeDialog(context, innerTap);
                                  return;
                                }
                                if (mullionDimTap != null) {
                                  _showMullionResizeDialog(
                                    context,
                                    mullionDimTap,
                                  );
                                  return;
                                }

                                if (isDoubleTap) {
                                  final double h = widget.model.height;
                                  if (modelPos.dy >= h - 30.0 &&
                                      modelPos.dy <= h + 250.0) {
                                    widget.model.toggleBottomWall();
                                    return;
                                  }

                                  if (tappedMullion &&
                                      tappedMullionIsHorizontal != null &&
                                      tappedMullionPosition != null) {
                                    widget.model.selectAt(
                                      modelPos,
                                      isLongPress: false,
                                    );
                                    _showMullionTypeDialog(context);
                                    return;
                                  }
                                }

                                if (widget.model.hasShutter &&
                                    !tappedZone &&
                                    !tappedMullion &&
                                    outerTap == DimensionTap.none &&
                                    innerTap == null &&
                                    mullionDimTap == null) {
                                  final double shutterTop =
                                  -widget.model.shutterBoxHeight;
                                  final double shutterBottom =
                                      widget.model.topSlantLeftY;
                                  if (modelPos.dy >= shutterTop - 20 &&
                                      modelPos.dy <= shutterBottom + 10 &&
                                      modelPos.dx >= -20 &&
                                      modelPos.dx <= widget.model.width + 20) {
                                    setState(() {
                                      _isShutterSelected = true;
                                      _isBottomPanelExpanded = true;
                                      _activeShutterTab = 0;
                                      widget.model.clearSelection();
                                    });
                                    if (_shutterLamesOptions.isEmpty &&
                                        _shutterCoulisseOptions.isEmpty) {
                                      _loadShutterOptions();
                                    }
                                    return;
                                  }
                                }

                                // In a coupled drawing the physical border
                                // selects that frame itself, not the content
                                // inside it.  Its eight resize handles then
                                // become available.
                                final frameAtBorder = _frameAtBorder(modelPos);
                                if (widget.model.isDrawingMode &&
                                    frameAtBorder != null) {
                                  setState(() {
                                    _isShutterSelected = false;
                                    _isBottomPanelExpanded = true;
                                  });
                                  widget.model.selectFrame(frameAtBorder.id);
                                  return;
                                }

                                setState(() {
                                  _isShutterSelected = false;
                                  _isBottomPanelExpanded = true;
                                });
                                widget.model.selectAt(
                                  modelPos,
                                  isLongPress: false,
                                );

                                if (isDoubleTap && tappedZone) {
                                  setState(() {
                                    _isLeftDrawerOpen = true;
                                  });
                                }
                              },
                              onLongPressStart: (details) async {
                                final modelPos = _getModelPos(
                                  details.localPosition,
                                );
                                WindowZone? tappedZ;
                                for (var z in widget.model.zones) {
                                  if (z.boundary.contains(modelPos)) {
                                    tappedZ = z;
                                    break;
                                  }
                                }

                                if (_isLeftDrawerOpen ||
                                    _paintbrushSecondsLeft > 0) {
                                  final specToApply =
                                      _activePaintGlassSpec ??
                                          (widget.model.selectedZone != null
                                              ? widget.model.selectedZone!
                                              .getGlassForCell(
                                            widget.model.activeSubZone,
                                          )
                                              : _tempGlassSpec);
                                  if (specToApply != null && tappedZ != null) {
                                    widget.model.paintAllZonesSpec(specToApply);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تم تعميم نوع البانو/الزجاج على جميع المناطق',
                                        ),
                                        backgroundColor: Colors.blue,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                    return;
                                  }
                                }

                                if (_isDrawerOpen || _isLeftDrawerOpen) {
                                  setState(() {
                                    _isDrawerOpen = false;
                                    _isLeftDrawerOpen = false;
                                  });
                                  return;
                                }
                                widget.model.selectAt(
                                  modelPos,
                                  isLongPress: true,
                                );

                                if (widget.model.selection.type ==
                                    SelectionType.mullion) {
                                  widget.model.deleteSelectedMullion();
                                  return;
                                }
                                if (widget.model.selection.type ==
                                    SelectionType.innerDivision) {
                                  widget.model.deleteSelectedInnerDivision();
                                  return;
                                }

                                final zone = widget.model.selectedZone;
                                final cellKey = widget.model.activeSubZone;
                                if (zone != null &&
                                    cellKey != null &&
                                    cellKey.contains('_cell_')) {
                                  final hasSash =
                                      zone.cellIsSash[cellKey] == true ||
                                          zone.cellIsDoubleSash[cellKey] ==
                                              true;
                                  if (hasSash) {
                                    final selected =
                                    await showDialog<Map<String, dynamic>>(
                                      context: context,
                                      builder: (context) =>
                                          ProfileSelectorDialog(
                                            profileType: 'sash',
                                            seriesId:
                                            activeSeriesForSystem?.id,
                                          ),
                                    );
                                    if (selected != null) {
                                      double price = 0.0;
                                      if (widget.model.selectedDbColor !=
                                          null) {
                                        int colorId =
                                        widget.model.selectedDbColor!['id'];
                                        final db = SqlDatabase();
                                        price = await db.getSectionPrice(
                                          selected['id'],
                                          colorId,
                                        );
                                      }
                                      final mutableSelected =
                                      Map<String, dynamic>.from(selected);
                                      mutableSelected['calculated_price'] =
                                          price;

                                      setState(() {
                                        final newOverrides =
                                        Map<
                                            String,
                                            Map<String, dynamic>
                                        >.from(zone.cellSashOverrides);
                                        newOverrides[cellKey] = mutableSelected;
                                        zone.cellSashOverrides = newOverrides;
                                        widget.model.refreshUI();
                                      });
                                    }
                                  }
                                }
                              },
                              onScaleStart: (details) {
                                if (_isDrawerOpen || _isLeftDrawerOpen) {
                                  setState(() {
                                    _isDrawerOpen = false;
                                    _isLeftDrawerOpen = false;
                                  });
                                }
                                _baseUserScale = _userScale;
                                _baseUserPan = _userPan;
                                _focalPointStart = details.localFocalPoint;

                                if (details.pointerCount < 2) {
                                  final modelPos = _getModelPos(
                                    details.localFocalPoint,
                                  );

                                  // Helper to map model coordinates to screen pixels for comfortable hit-testing
                                  Offset modelToScreen(Offset mPos) {
                                    return _modelToScreen(mPos);
                                  }

                                  final tlScreen = modelToScreen(
                                    Offset(0, widget.model.topSlantLeftY),
                                  );
                                  final trScreen = modelToScreen(
                                    Offset(
                                      widget.model.width,
                                      widget.model.topSlantRightY,
                                    ),
                                  );
                                  final tcScreen = modelToScreen(
                                    Offset(
                                      widget.model.width / 2,
                                      math.min(
                                        widget.model.topSlantLeftY,
                                        widget.model.topSlantRightY,
                                      ) -
                                          (widget.model.archHeight * 2),
                                    ),
                                  );
                                  final touchScreen = details.localFocalPoint;
                                  const double hitRadius = 35.0;

                                  final isFrameSelected =
                                      widget.model.selection.type ==
                                          SelectionType.frame;
                                  final frameResizeHandle =
                                      _frameResizeHandleAt(touchScreen);
                                  if (frameResizeHandle != null &&
                                      widget.model.selection.zoneId != null) {
                                    _draggedFrameResizeHandle =
                                        frameResizeHandle;
                                    _draggedFrameZoneId =
                                        widget.model.selection.zoneId;
                                    _frameResizeHistorySaved = false;
                                  } else if (isFrameSelected &&
                                      widget.model.selection.zoneId == null &&
                                      widget.model.isDrawingMode &&
                                      widget.model.canBeArchedOrSlanted &&
                                      (touchScreen - tlScreen).distance <
                                          hitRadius) {
                                    _isDraggingSlantLeft = true;
                                  } else if (isFrameSelected &&
                                      widget.model.selection.zoneId == null &&
                                      widget.model.isDrawingMode &&
                                      widget.model.canBeArchedOrSlanted &&
                                      (touchScreen - trScreen).distance <
                                          hitRadius) {
                                    _isDraggingSlantRight = true;
                                  } else if (isFrameSelected &&
                                      widget.model.selection.zoneId == null &&
                                      widget.model.isDrawingMode &&
                                      widget.model.canBeArchedOrSlanted &&
                                      (touchScreen - tcScreen).distance <
                                          hitRadius) {
                                    _isDraggingArch = true;
                                  } else if (widget.model.selectedZone !=
                                      null &&
                                      widget.model.selectedZone!.boundary
                                          .contains(modelPos) &&
                                      widget.model.isDrawingMode) {
                                    final zone = widget.model.selectedZone!;
                                    final bounds = zone.boundary;
                                    final isTopBound = _isTopZone(zone);
                                    final double topOffset =
                                    widget.model.hasShutter
                                        ? widget.model.shutterBoxHeight
                                        : 0.0;

                                    bool hitHandle = false;
                                    bool hitHinge = false;

                                    if (zone.content ==
                                        ZoneContent.singleSash ||
                                        zone.content ==
                                            ZoneContent.doubleSash) {
                                      final isLeftActive =
                                      (zone.openDirection ==
                                          OpenDirection.left);
                                      final activeIsRight =
                                      !isLeftActive; // fallback/default

                                      final sep = 4.0;
                                      final midX =
                                          bounds.left +
                                              bounds.width *
                                                  zone.doubleSashRatio;
                                      final leftR = Rect.fromLTRB(
                                        bounds.left,
                                        bounds.top,
                                        midX - sep / 2,
                                        bounds.bottom,
                                      );
                                      final rightR = Rect.fromLTRB(
                                        midX + sep / 2,
                                        bounds.top,
                                        bounds.right,
                                        bounds.bottom,
                                      );

                                      final sashRect =
                                      (zone.content ==
                                          ZoneContent.doubleSash)
                                          ? (activeIsRight ? rightR : leftR)
                                          : bounds;

                                      final handleSide =
                                      (zone.content ==
                                          ZoneContent.doubleSash)
                                          ? (activeIsRight
                                          ? OpenDirection.left
                                          : OpenDirection.right)
                                          : zone.openDirection!;

                                      // Precise hit testing for handle
                                      double hRatio =
                                          zone.handlePositionRatio ?? 0.5;
                                      double hX = sashRect.center.dx;
                                      double hY = sashRect.center.dy;

                                      if (handleSide == OpenDirection.left) {
                                        hX = sashRect.left + 20;
                                        double topYVal = getSashTopY(
                                          hX,
                                          sashRect.top,
                                          widget.model.profileThickness,
                                          topOffset,
                                          isTopBound,
                                        );
                                        hY =
                                            topYVal +
                                                ((sashRect.bottom - topYVal) *
                                                    (1.0 - hRatio));
                                      } else if (handleSide ==
                                          OpenDirection.right) {
                                        hX = sashRect.right - 20;
                                        double topYVal = getSashTopY(
                                          hX,
                                          sashRect.top,
                                          widget.model.profileThickness,
                                          topOffset,
                                          isTopBound,
                                        );
                                        hY =
                                            topYVal +
                                                ((sashRect.bottom - topYVal) *
                                                    (1.0 - hRatio));
                                      } else if (handleSide ==
                                          OpenDirection.top) {
                                        hX =
                                            sashRect.left +
                                                (sashRect.width * hRatio);
                                        double topYVal = getSashTopY(
                                          hX,
                                          sashRect.top,
                                          widget.model.profileThickness,
                                          topOffset,
                                          isTopBound,
                                        );
                                        hY = topYVal + 22;
                                      } else if (handleSide ==
                                          OpenDirection.bottom) {
                                        hY = sashRect.bottom - 22;
                                        hX =
                                            sashRect.left +
                                                (sashRect.width * hRatio);
                                      }

                                      final handleScreenPos = modelToScreen(
                                        Offset(hX, hY),
                                      );
                                      if ((touchScreen - handleScreenPos)
                                          .distance <
                                          45.0) {
                                        _isDraggingHandle = true;
                                        hitHandle = true;
                                      }

                                      // Precise hit testing for hinges
                                      bool hingesOnLeft = false;
                                      bool hingesOnRight = false;
                                      bool hingesOnTop = false;
                                      bool hingesOnBottom = false;

                                      if (zone.content ==
                                          ZoneContent.doubleSash) {
                                        hingesOnLeft = !activeIsRight;
                                        hingesOnRight = activeIsRight;
                                      } else {
                                        hingesOnLeft =
                                        (zone.openDirection ==
                                            OpenDirection.right);
                                        hingesOnRight =
                                        (zone.openDirection ==
                                            OpenDirection.left);
                                        hingesOnTop =
                                        (zone.openDirection ==
                                            OpenDirection.bottom);
                                        hingesOnBottom =
                                        (zone.openDirection ==
                                            OpenDirection.top);
                                      }

                                      double sashHeight = sashRect.height;
                                      int hingeCount = (sashHeight > 2100)
                                          ? 4
                                          : (sashHeight > 1000)
                                          ? 3
                                          : 2;
                                      if (zone.glass.structure ==
                                          GlassStructure.double) {
                                        hingeCount += 1;
                                      }

                                      if (hingeCount >= 3 && !hitHandle) {
                                        double hgX = 0;
                                        double hgY = 0;
                                        final hingeRevealOffset =
                                        (widget.model.profileThickness *
                                            0.28)
                                            .clamp(9.0, 18.0)
                                            .toDouble();
                                        if (hingesOnLeft || hingesOnRight) {
                                          hgX = hingesOnRight
                                              ? sashRect.right +
                                              hingeRevealOffset
                                              : sashRect.left -
                                              hingeRevealOffset;
                                          double startY =
                                              getSashTopY(
                                                hgX,
                                                sashRect.top,
                                                widget.model.profileThickness,
                                                topOffset,
                                                isTopBound,
                                              ) +
                                                  100;
                                          double step =
                                              (sashRect.bottom - 100 - startY) /
                                                  (hingeCount - 1);
                                          hgY =
                                              startY +
                                                  step +
                                                  zone.middleHingeDragOffset;
                                        } else if (hingesOnTop ||
                                            hingesOnBottom) {
                                          hgY = hingesOnBottom
                                              ? sashRect.bottom +
                                              hingeRevealOffset
                                              : sashRect.top -
                                              hingeRevealOffset;
                                          double startX = sashRect.left + 100;
                                          double step =
                                              (sashRect.right - 100 - startX) /
                                                  (hingeCount - 1);
                                          hgX =
                                              startX +
                                                  step +
                                                  zone.middleHingeDragOffset;
                                          if (hingesOnTop) {
                                            hgY =
                                                getSashTopY(
                                                  hgX,
                                                  sashRect.top,
                                                  widget.model.profileThickness,
                                                  topOffset,
                                                  isTopBound,
                                                ) -
                                                    hingeRevealOffset;
                                          }
                                        }
                                        final hingeScreenPos = modelToScreen(
                                          Offset(hgX, hgY),
                                        );
                                        if ((touchScreen - hingeScreenPos)
                                            .distance <
                                            45.0) {
                                          _isDraggingHinge = true;
                                          hitHinge = true;
                                        }
                                      }
                                    } else if (zone.content ==
                                        ZoneContent.slidingSash) {
                                      int count = zone.slidingSashesCount;
                                      if (count < 2) count = 2;
                                      double frameT =
                                          zone.sashThickness ??
                                              widget.model.getSectionThickness(
                                                'sash',
                                                fallback: 45.0,
                                              );
                                      double sashWidth =
                                          (bounds.width +
                                              (count - 1) * frameT) /
                                              count;

                                      // Left sash (i=0)
                                      double left0 = bounds.left;
                                      Rect sashRectLeft = Rect.fromLTRB(
                                        left0,
                                        bounds.top,
                                        left0 + sashWidth,
                                        bounds.bottom,
                                      );

                                      // Right sash (i=count-1)
                                      double leftN =
                                          bounds.left +
                                              (count - 1) *
                                                  (sashWidth - frameT);
                                      Rect sashRectRight = Rect.fromLTRB(
                                        leftN,
                                        bounds.top,
                                        leftN + sashWidth,
                                        bounds.bottom,
                                      );

                                      double hRatio =
                                          zone.handlePositionRatio ?? 0.5;

                                      // Left handle (OpenDirection.left on sashRectLeft)
                                      double hXLeft = sashRectLeft.left + 20;
                                      double topYLeft = getSashTopY(
                                        hXLeft,
                                        sashRectLeft.top,
                                        widget.model.profileThickness,
                                        topOffset,
                                        isTopBound,
                                      );
                                      double hYLeft =
                                          topYLeft +
                                              ((sashRectLeft.bottom -
                                                  topYLeft) *
                                                  (1.0 - hRatio));

                                      // Right handle (OpenDirection.right on sashRectRight)
                                      double hXRight = sashRectRight.right - 20;
                                      double topYRight = getSashTopY(
                                        hXRight,
                                        sashRectRight.top,
                                        widget.model.profileThickness,
                                        topOffset,
                                        isTopBound,
                                      );
                                      double hYRight =
                                          topYRight +
                                              ((sashRectRight.bottom -
                                                  topYRight) *
                                                  (1.0 - hRatio));

                                      final handleScreenPosLeft = modelToScreen(
                                        Offset(hXLeft, hYLeft),
                                      );
                                      final handleScreenPosRight =
                                      modelToScreen(
                                        Offset(hXRight, hYRight),
                                      );

                                      if ((touchScreen - handleScreenPosLeft)
                                          .distance <
                                          45.0 ||
                                          (touchScreen - handleScreenPosRight)
                                              .distance <
                                              45.0) {
                                        _isDraggingHandle = true;
                                        hitHandle = true;
                                      }
                                    }

                                    if (hitHandle || hitHinge) {
                                      // Done, drag started for handle or hinge
                                    } else {
                                      final dividerX =
                                          bounds.left +
                                              bounds.width *
                                                  zone.doubleSashRatio;
                                      final dividerTop = _modelToScreen(
                                        Offset(dividerX, bounds.top),
                                      );
                                      final dividerBottom = _modelToScreen(
                                        Offset(dividerX, bounds.bottom),
                                      );
                                      final dividerScreenX = dividerTop.dx;
                                      final topScreenY = dividerTop.dy;
                                      final bottomScreenY = dividerBottom.dy;
                                      final double dist =
                                      (touchScreen.dx - dividerScreenX)
                                          .abs();

                                      if (zone.content ==
                                          ZoneContent.doubleSash &&
                                          dist < 30.0 &&
                                          touchScreen.dy >= topScreenY &&
                                          touchScreen.dy <= bottomScreenY) {
                                        widget.model.selectAt(
                                          modelPos,
                                          isLongPress: true,
                                        );
                                        _isDraggingDoubleSashDivider = true;
                                      } else if ((zone.content ==
                                          ZoneContent.singleSash ||
                                          zone.content ==
                                              ZoneContent.doubleSash) &&
                                          (() {
                                            final sashT =
                                                zone.sashThickness ??
                                                    widget.model
                                                        .profileThickness;
                                            if (zone.content ==
                                                ZoneContent.doubleSash) {
                                              final sep = 4.0;
                                              final midX =
                                                  bounds.left +
                                                      bounds.width *
                                                          zone.doubleSashRatio;
                                              final leftR = Rect.fromLTRB(
                                                bounds.left,
                                                bounds.top,
                                                midX - sep / 2,
                                                bounds.bottom,
                                              );
                                              final rightR = Rect.fromLTRB(
                                                midX + sep / 2,
                                                bounds.top,
                                                bounds.right,
                                                bounds.bottom,
                                              );
                                              final leftGlassR = widget.model
                                                  .getSafeGlassRect(
                                                leftR,
                                                sashT,
                                              );
                                              final rightGlassR = widget.model
                                                  .getSafeGlassRect(
                                                rightR,
                                                sashT,
                                              );
                                              return _checkAndStartSashDividerDrag(
                                                zone.id,
                                                false,
                                                leftGlassR,
                                                zone.innerH,
                                                zone.innerV,
                                                zone.innerHPositions,
                                                zone.innerVPositions,
                                                touchScreen,
                                              ) ||
                                                  _checkAndStartSashDividerDrag(
                                                    zone.id,
                                                    true,
                                                    rightGlassR,
                                                    zone.rightInnerH,
                                                    zone.rightInnerV,
                                                    zone.rightInnerHPositions,
                                                    zone.rightInnerVPositions,
                                                    touchScreen,
                                                  );
                                            } else {
                                              final glassR = widget.model
                                                  .getSafeGlassRect(
                                                bounds,
                                                sashT,
                                              );
                                              return _checkAndStartSashDividerDrag(
                                                zone.id,
                                                false,
                                                glassR,
                                                zone.innerH,
                                                zone.innerV,
                                                zone.innerHPositions,
                                                zone.innerVPositions,
                                                touchScreen,
                                              );
                                            }
                                          })()) {
                                        // Started dragging sash division
                                      } else if ((() {
                                        if (zone.glass.structure ==
                                            GlassStructure.double) {
                                          final sashT =
                                              zone.sashThickness ??
                                                  widget.model.profileThickness;
                                          if (zone.content ==
                                              ZoneContent.doubleSash) {
                                            final sep = 4.0;
                                            final midX =
                                                bounds.left +
                                                    bounds.width *
                                                        zone.doubleSashRatio;
                                            final leftR = Rect.fromLTRB(
                                              bounds.left,
                                              bounds.top,
                                              midX - sep / 2,
                                              bounds.bottom,
                                            );
                                            final rightR = Rect.fromLTRB(
                                              midX + sep / 2,
                                              bounds.top,
                                              bounds.right,
                                              bounds.bottom,
                                            );
                                            final leftGlassR = widget.model
                                                .getSafeGlassRect(leftR, sashT);
                                            final rightGlassR = widget.model
                                                .getSafeGlassRect(
                                              rightR,
                                              sashT,
                                            );
                                            return _checkAndStartGlassDecorDrag(
                                              zone.id,
                                              leftGlassR,
                                              zone.glass,
                                              touchScreen,
                                            ) ||
                                                _checkAndStartGlassDecorDrag(
                                                  zone.id,
                                                  rightGlassR,
                                                  zone.glass,
                                                  touchScreen,
                                                );
                                          } else {
                                            final glassR = widget.model
                                                .getSafeGlassRect(
                                              bounds,
                                              sashT,
                                            );
                                            return _checkAndStartGlassDecorDrag(
                                              zone.id,
                                              glassR,
                                              zone.glass,
                                              touchScreen,
                                            );
                                          }
                                        }
                                        return false;
                                      })()) {
                                        // Started dragging glass decoration
                                      } else {
                                        // Defer drawing start — wait for real drag in onScaleUpdate
                                        widget.model.pendingDrawStart =
                                            modelPos;
                                      }
                                    }
                                  } else if (widget.model.isDrawingMode &&
                                      widget.model.selection.type !=
                                          SelectionType.mullion) {
                                    widget.model.pendingDrawStart = modelPos;
                                  }
                                }
                              },
                              onScaleUpdate: (details) {
                                if (details.pointerCount >= 2) {
                                  setState(() {
                                    double newScale =
                                    (_baseUserScale * details.scale).clamp(
                                      0.5,
                                      5.0,
                                    );
                                    _userScale = newScale;
                                    final canvasOrigin = Offset(
                                      widget.model.canvasDx,
                                      widget.model.canvasDy,
                                    );
                                    _userPan =
                                        details.localFocalPoint -
                                            canvasOrigin -
                                            (details.localFocalPoint -
                                                canvasOrigin -
                                                _baseUserPan) *
                                                (newScale / _baseUserScale);
                                  });
                                } else {
                                  final modelPos = _getModelPos(
                                    details.localFocalPoint,
                                  );
                                  // Commit pendingDrawStart → real drawing only after
                                  // the finger has actually moved (≥5 logical pixels)
                                  if (widget.model.drawingStart == null &&
                                      widget.model.pendingDrawStart != null) {
                                    final pending =
                                    widget.model.pendingDrawStart!;
                                    final screenPending =
                                    _modelToScreen(pending);
                                    if ((details.localFocalPoint -
                                        screenPending)
                                        .distance >=
                                        5.0) {
                                      widget.model.startDrawing(pending);
                                    }
                                  }
                                  if (widget.model.drawingStart != null) {
                                    widget.model.updateDrawing(modelPos);
                                  } else if (_draggedFrameResizeHandle !=
                                          null &&
                                      _draggedFrameZoneId != null &&
                                      widget.model.isDrawingMode) {
                                    final handle = _draggedFrameResizeHandle!;
                                    final deltaX =
                                        details.focalPointDelta.dx /
                                            (_userScale *
                                                widget.model.canvasScale);
                                    final deltaY =
                                        details.focalPointDelta.dy /
                                            (_userScale *
                                                widget.model.canvasScale);
                                    widget.model.resizeFrameFromHandles(
                                      _draggedFrameZoneId!,
                                      moveLeft:
                                          handle == _FrameResizeHandle.left ||
                                              handle ==
                                                  _FrameResizeHandle.topLeft ||
                                              handle ==
                                                  _FrameResizeHandle
                                                      .bottomLeft,
                                      moveRight:
                                          handle == _FrameResizeHandle.right ||
                                              handle ==
                                                  _FrameResizeHandle.topRight ||
                                              handle ==
                                                  _FrameResizeHandle
                                                      .bottomRight,
                                      moveTop:
                                          handle == _FrameResizeHandle.top ||
                                              handle ==
                                                  _FrameResizeHandle.topLeft ||
                                              handle ==
                                                  _FrameResizeHandle.topRight,
                                      moveBottom: handle ==
                                              _FrameResizeHandle.bottom ||
                                          handle == _FrameResizeHandle
                                              .bottomLeft ||
                                          handle == _FrameResizeHandle
                                              .bottomRight,
                                      deltaX: deltaX,
                                      deltaY: deltaY,
                                      saveHistory: !_frameResizeHistorySaved,
                                    );
                                    _frameResizeHistorySaved = true;
                                  } else if (_isDraggingSlantLeft) {
                                    double dy =
                                        details.focalPointDelta.dy /
                                            (_userScale *
                                                widget.model.canvasScale);
                                    widget.model.updateTopSlantAndArch(
                                      leftSlant:
                                      (widget.model.topSlantLeftY + dy)
                                          .clamp(-500.0, 500.0),
                                    );
                                  } else if (_isDraggingSlantRight) {
                                    double dy =
                                        details.focalPointDelta.dy /
                                            (_userScale *
                                                widget.model.canvasScale);
                                    widget.model.updateTopSlantAndArch(
                                      rightSlant:
                                      (widget.model.topSlantRightY + dy)
                                          .clamp(-500.0, 500.0),
                                    );
                                  } else if (_isDraggingArch) {
                                    double dy =
                                        details.focalPointDelta.dy /
                                            (_userScale *
                                                widget.model.canvasScale);
                                    widget.model.updateTopSlantAndArch(
                                      arch: (widget.model.archHeight - dy / 2)
                                          .clamp(0.0, 800.0),
                                    );
                                  } else if (widget.model.selection.type ==
                                      SelectionType.mullion) {
                                    widget.model.moveSelectedMullion(
                                      (widget
                                          .model
                                          .selection
                                          .isHorizontalMullion!
                                          ? details.focalPointDelta.dy
                                          : details.focalPointDelta.dx) /
                                          (_userScale *
                                              widget.model.canvasScale),
                                    );
                                  } else if (widget.model.selection.type ==
                                      SelectionType.innerDivision) {
                                    double deltaX =
                                        details.focalPointDelta.dx /
                                            (_userScale *
                                                widget.model.canvasScale);
                                    double deltaY =
                                        details.focalPointDelta.dy /
                                            (_userScale *
                                                widget.model.canvasScale);
                                    widget.model.moveSelectedInnerDivision(
                                      deltaX,
                                      deltaY,
                                    );
                                  } else if (_isDraggingDecor &&
                                      _draggedDecorZoneId != null &&
                                      widget.model.isDrawingMode) {
                                    final zone = widget.model.zones.firstWhere(
                                          (z) => z.id == _draggedDecorZoneId,
                                    );
                                    final sashT =
                                        zone.sashThickness ??
                                            widget.model.profileThickness;
                                    Rect parentR = zone.boundary;
                                    Rect sashR = parentR;
                                    if (zone.content ==
                                        ZoneContent.doubleSash) {
                                      final sep = 4.0;
                                      final midX =
                                          parentR.left +
                                              parentR.width *
                                                  zone.doubleSashRatio;
                                      if (modelPos.dx < midX) {
                                        sashR = Rect.fromLTRB(
                                          parentR.left,
                                          parentR.top,
                                          midX - sep / 2,
                                          parentR.bottom,
                                        );
                                      } else {
                                        sashR = Rect.fromLTRB(
                                          midX + sep / 2,
                                          parentR.top,
                                          parentR.right,
                                          parentR.bottom,
                                        );
                                      }
                                    }
                                    final glassR = widget.model
                                        .getSafeGlassRect(sashR, sashT);

                                    if (_draggedDecorIsHorizontal) {
                                      double newRatio =
                                          (modelPos.dy - glassR.top) /
                                              glassR.height;
                                      newRatio = newRatio.clamp(0.02, 0.98);
                                      widget.model.updateZoneGlassDecorHPos(
                                        _draggedDecorZoneId!,
                                        _draggedDecorIndex,
                                        newRatio,
                                      );
                                    } else {
                                      double newRatio =
                                          (modelPos.dx - glassR.left) /
                                              glassR.width;
                                      newRatio = newRatio.clamp(0.02, 0.98);
                                      widget.model.updateZoneGlassDecorVPos(
                                        _draggedDecorZoneId!,
                                        _draggedDecorIndex,
                                        newRatio,
                                      );
                                    }
                                  } else if (_isDraggingDoubleSashDivider &&
                                      widget.model.selectedZone != null &&
                                      widget.model.isDrawingMode) {
                                    final zone = widget.model.selectedZone!;
                                    final bounds = zone.boundary;
                                    double newRatio =
                                        (modelPos.dx - bounds.left) /
                                            bounds.width;
                                    newRatio = newRatio.clamp(0.15, 0.85);
                                    widget.model.updateZoneDoubleSashRatio(
                                      zone.id,
                                      newRatio,
                                    );
                                  } else if (_isDraggingSashDivision &&
                                      _draggedSashZoneId != null &&
                                      widget.model.isDrawingMode) {
                                    final zone = widget.model.zones.firstWhere(
                                          (z) => z.id == _draggedSashZoneId,
                                    );
                                    final isRight = _draggedSashIsRight;
                                    final sashT =
                                        zone.sashThickness ??
                                            widget.model.profileThickness;
                                    Rect parentR = zone.boundary;
                                    Rect sashR = parentR;
                                    if (zone.content ==
                                        ZoneContent.doubleSash) {
                                      final sep = 4.0;
                                      final midX =
                                          parentR.left +
                                              parentR.width *
                                                  zone.doubleSashRatio;
                                      if (!isRight) {
                                        sashR = Rect.fromLTRB(
                                          parentR.left,
                                          parentR.top,
                                          midX - sep / 2,
                                          parentR.bottom,
                                        );
                                      } else {
                                        sashR = Rect.fromLTRB(
                                          midX + sep / 2,
                                          parentR.top,
                                          parentR.right,
                                          parentR.bottom,
                                        );
                                      }
                                    }
                                    final glassR = widget.model
                                        .getSafeGlassRect(sashR, sashT);

                                    if (_draggedSashIsHorizontal) {
                                      double newRatio =
                                          (modelPos.dy - glassR.top) /
                                              glassR.height;
                                      widget.model
                                          .updateZoneInnerHDivisionRatio(
                                        _draggedSashZoneId!,
                                        isRight,
                                        _draggedSashIndex,
                                        newRatio,
                                      );
                                    } else {
                                      double newRatio =
                                          (modelPos.dx - glassR.left) /
                                              glassR.width;
                                      widget.model
                                          .updateZoneInnerVDivisionRatio(
                                        _draggedSashZoneId!,
                                        isRight,
                                        _draggedSashIndex,
                                        newRatio,
                                      );
                                    }
                                  } else if (_isDraggingHinge &&
                                      widget.model.selectedZone != null &&
                                      widget.model.isDrawingMode) {
                                    _handleHingeDrag(
                                      details.focalPointDelta,
                                      widget.model.selectedZone!,
                                    );
                                  } else if (_isDraggingHandle &&
                                      widget.model.selectedZone != null &&
                                      widget.model.isDrawingMode) {
                                    _handleHandleDrag(
                                      details.focalPointDelta,
                                      widget.model.selectedZone!,
                                    );
                                  } else if (!widget.model.isDrawingMode) {
                                    setState(() {
                                      _userPan =
                                          _baseUserPan +
                                              (details.localFocalPoint -
                                                  _focalPointStart);
                                    });
                                  }
                                }
                              },
                              onScaleEnd: (details) {
                                if (widget.model.drawingStart != null) {
                                  widget.model.endDrawing();
                                }
                                bool wasDraggingProperty =
                                    _isDraggingSlantLeft ||
                                        _isDraggingSlantRight ||
                                        _isDraggingArch ||
                                        _isDraggingDoubleSashDivider ||
                                        _isDraggingSashDivision ||
                                        _isDraggingDecor ||
                                        _isDraggingHinge ||
                                        _isDraggingHandle;
                                if (wasDraggingProperty) {
                                  widget.model.saveSnapshotOutside();
                                }
                                _isDraggingHandle = false;
                                _isDraggingHinge = false;
                                _isDraggingSlantLeft = false;
                                _isDraggingSlantRight = false;
                                _isDraggingArch = false;
                                _isDraggingDoubleSashDivider = false;
                                _isDraggingSashDivision = false;
                                _isDraggingDecor = false;
                                _draggedSashZoneId = null;
                                _draggedDecorZoneId = null;
                                _draggedFrameResizeHandle = null;
                                _draggedFrameZoneId = null;
                                _frameResizeHistorySaved = false;
                              },
                              child: Listener(
                                onPointerSignal: _handleDrawingPointerSignal,
                                child: MouseRegion(
                                  cursor: _isWindowsDesktop
                                      ? SystemMouseCursors.precise
                                      : MouseCursor.defer,
                                  child: Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    decoration: BoxDecoration(
                                      color:
                                      Theme
                                          .of(context)
                                          .brightness ==
                                          Brightness.dark
                                          ? const Color(0xFF232332)
                                          : const Color(0xFFF5F5F5),
                                    ),
                                    child: CustomPaint(
                                      size: Size(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                      ),
                                      painter: AppWorkspacePainter(
                                        model: widget.model,
                                        userScale: _userScale,
                                        userPan: _userPan,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_isWindowsDesktop)
                              Positioned(
                                top: 18,
                                right: _paintbrushSecondsLeft > 0 ? 150 : 18,
                                child: Offstage(
                                  offstage: true,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme
                                            .of(
                                          context,
                                        )
                                            .cardColor
                                            .withValues(alpha: 0.94),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Theme
                                              .of(
                                            context,
                                          )
                                              .dividerColor
                                              .withValues(alpha: 0.7),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.18,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Semantics(
                                            button: true,
                                            label: 'تكبير الرسم',
                                            child: IconButton(
                                              icon: const Icon(Icons.add),
                                              onPressed: () =>
                                                  _changeDrawingZoom(
                                                    _zoomStep,
                                                    Offset(
                                                      constraints.maxWidth / 2,
                                                      constraints.maxHeight / 2,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                          Container(
                                            width: 26,
                                            height: 1,
                                            color: Theme
                                                .of(
                                              context,
                                            )
                                                .dividerColor,
                                          ),
                                          Semantics(
                                            button: true,
                                            label: 'تصغير الرسم',
                                            child: IconButton(
                                              icon: const Icon(Icons.remove),
                                              onPressed: () =>
                                                  _changeDrawingZoom(
                                                    1 / _zoomStep,
                                                    Offset(
                                                      constraints.maxWidth / 2,
                                                      constraints.maxHeight / 2,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                          Container(
                                            width: 26,
                                            height: 1,
                                            color: Theme
                                                .of(
                                              context,
                                            )
                                                .dividerColor,
                                          ),
                                          Semantics(
                                            button: true,
                                            label: 'إعادة حجم الرسم',
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons
                                                    .center_focus_strong_outlined,
                                              ),
                                              onPressed: _resetDrawingZoom,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_paintbrushSecondsLeft > 0 &&
                                (_activePaintFinish != null ||
                                    _activePaintZoneContent != null ||
                                    _activePaintCellSash ||
                                    _activePaintCellPanel ||
                                    _activePaintGlassSpec != null))
                              Positioned(
                                top: 20,
                                right: 20,
                                child: GestureDetector(
                                  onTap: _cancelPaintbrushMode,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.blue.shade700,
                                          Colors.blue.shade400,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.colorize_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          '$_paintbrushSecondsLeft ث',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white70,
                                          size: 14,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  _buildInteractiveBottomPanel(context),
                ],
              ),

              // 🟢 القائمة الجانبية اليسرى (Left Drawer) لخصائص الزجاج
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                left: _isLeftDrawerOpen ? 0 : -330,
                top: 15,
                bottom: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 330,
                      decoration: BoxDecoration(
                        color: Theme
                            .of(context)
                            .brightness == Brightness.dark
                            ? const Color(0xFF1E1E2C)
                            : Colors.white,
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(5, 0),
                          ),
                        ],
                      ),
                      child: _buildLeftDrawerContent(context),
                    ),
                    GestureDetector(
                      onTap: () =>
                          setState(
                                () => _isLeftDrawerOpen = !_isLeftDrawerOpen,
                          ),
                      onVerticalDragUpdate: (details) {
                        setState(() {
                          _leftDrawerHandleTop += details.delta.dy;
                          if (_leftDrawerHandleTop < 0) {
                            _leftDrawerHandleTop = 0;
                          }
                          double maxTop =
                              MediaQuery
                                  .of(context)
                                  .size
                                  .height -
                                  120 -
                                  70 -
                                  15;
                          if (_leftDrawerHandleTop > maxTop) {
                            _leftDrawerHandleTop = maxTop;
                          }
                        });
                      },
                      child: Container(
                        margin: EdgeInsets.only(top: _leftDrawerHandleTop),
                        width: 40,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Theme
                              .of(context)
                              .brightness == Brightness.dark
                              ? const Color(0xFF1E1E2C)
                              : Colors.white,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(15),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(2, 0),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isLeftDrawerOpen
                              ? Icons.keyboard_double_arrow_left_rounded
                              : Icons.keyboard_double_arrow_right_rounded,
                          color: Theme
                              .of(context)
                              .brightness == Brightness.dark
                              ? Colors.blue.shade300
                              : Colors.blue.shade800,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🟢 طبقة التعتيم لإغلاق القائمة عند النقر خارجها
              if (_isDrawerOpen)
                GestureDetector(
                  onTap: () => setState(() => _isDrawerOpen = false),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.1),
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),

              // 🟢 القائمة الجانبية (Drawer)
              // 🟢 القائمة الجانبية (Drawer) بعد التعديل لتخفيف الازدحام السفلي
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                right: _isDrawerOpen ? 0 : -330,
                top: 15,
                // 🟢 رفعناها لتكون في الجزء العلوي من الشاشة
                bottom: 120,
                // 🟢 ترك مسافة كبيرة جداً من الأسفل لمنع التداخل
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // 🟢 جعل زر السحب في الأعلى بدلاً من المنتصف
                  children: [
                    GestureDetector(
                      onTap: () =>
                          setState(() => _isDrawerOpen = !_isDrawerOpen),
                      onVerticalDragUpdate: (details) {
                        setState(() {
                          _rightDrawerHandleTop += details.delta.dy;
                          if (_rightDrawerHandleTop < 0) {
                            _rightDrawerHandleTop = 0;
                          }
                          double maxTop =
                              MediaQuery
                                  .of(context)
                                  .size
                                  .height -
                                  120 -
                                  70 -
                                  15;
                          if (_rightDrawerHandleTop > maxTop) {
                            _rightDrawerHandleTop = maxTop;
                          }
                        });
                      },
                      child: Container(
                        margin: EdgeInsets.only(top: _rightDrawerHandleTop),
                        // 🟢 إزاحة بسيطة للزر ليكون شكله أنيقاً
                        width: 40,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Theme
                              .of(context)
                              .brightness == Brightness.dark
                              ? const Color(0xFF1E1E2C)
                              : Colors.white,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(15),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(-2, 0),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isDrawerOpen
                              ? Icons.keyboard_double_arrow_right_rounded
                              : Icons.keyboard_double_arrow_left_rounded,
                          color: Theme
                              .of(context)
                              .brightness == Brightness.dark
                              ? Colors.blue.shade300
                              : Colors.blue.shade800,
                          size: 26,
                        ),
                      ),
                    ),
                    Container(
                      width: 330,
                      decoration: BoxDecoration(
                        color: Theme
                            .of(context)
                            .brightness == Brightness.dark
                            ? const Color(0xFF1E1E2C)
                            : Colors.white,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(-5, 0),
                          ),
                        ],
                      ),
                      child: _buildDrawerContent(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeftDrawerContent(BuildContext context) {
    return ScrollConfiguration(
      behavior: _drawerScrollBehavior(context, scrollbars: false),
      child: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final isDark = Theme
              .of(context)
              .brightness == Brightness.dark;
          final lang = Provider
              .of<AppSettingsProvider>(context)
              .language;
          final WindowZone? zone = widget.model.selectedZone;
          WindowZone? targetZone = zone;
          if (targetZone == null ||
              targetZone.content != ZoneContent.doubleSash) {
            for (var z in widget.model.zones) {
              if (z.content == ZoneContent.doubleSash) {
                targetZone = z;
                break;
              }
            }
          }

          Widget buildPaintbrushButton({
            required String label,
            required IconData icon,
            required GlassFinish finish,
            required GlassStructure structure,
          }) {
            final isSelected =
                _activePaintFinish == finish && _paintbrushSecondsLeft > 0;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ContentButton(
                label: label,
                icon: icon,
                selected: isSelected,
                onPressed: () {
                  _startPaintbrushMode(finish: finish, structure: structure);
                },
              ),
            );
          }

          // This value reflects the whole drawing, not merely the last cell
          // selected by the user. Mixed glass drawings intentionally show
          // the neutral default state.
          final GlassSpecification spec = _tempGlassSpec;
          final structure = spec.structure;

          GlassSpecification fitDoubleGlassToParclose(
              GlassSpecification candidate,) {
            if (candidate.structure != GlassStructure.double) {
              return candidate;
            }
            final suggested = widget.model
                .suggestedIntercallThicknessForDoubleGlass(
              thicknessOuter: candidate.thicknessOuter ?? 4.0,
              thicknessInner: candidate.thicknessInner ?? 4.0,
            );
            return suggested == null
                ? candidate
                : candidate.copyWith(intercallThickness: suggested);
          }

          Widget? buildParcloseThicknessInfo() {
            final maximum = widget.model.selectedParcloseMaxGlassThickness;
            if (maximum == null || spec.structure == GlassStructure.closed) {
              return null;
            }

            final total = spec.totalThickness(widget.model.allGlassCache);
            final difference = total - maximum;
            final isExact = difference.abs() < 0.01;
            final isAbove = difference > 0;
            final color = isExact
                ? Colors.green.shade700
                : (isAbove ? Colors.red.shade700 : Colors.orange.shade800);
            final icon = isExact
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded;
            final message = isExact
                ? 'سُمك الزجاج مطابق لسعة البيركلوز: ${total.toStringAsFixed(
                0)} مم'
                : isAbove
                ? 'تنبيه: سُمك الزجاج ${total.toStringAsFixed(
                0)} مم أكبر من سعة البيركلوز ${maximum.toStringAsFixed(0)} مم'
                : 'تنبيه: سُمك الزجاج ${total.toStringAsFixed(
                0)} مم أصغر من سعة البيركلوز ${maximum.toStringAsFixed(0)} مم';

            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final parcloseThicknessInfo = buildParcloseThicknessInfo();
          final fallbackIntercallChoices = <Map<String, dynamic>>[
            {'thickness': 6, 'name': '6 مم'},
            {'thickness': 8, 'name': '8 مم'},
            {'thickness': 10, 'name': '10 مم'},
            {'thickness': 12, 'name': '12 مم'},
            {'thickness': 14, 'name': '14 مم'},
            {'thickness': 16, 'name': '16 مم'},
          ];
          final intercallChoices = List<Map<String, dynamic>>.from(
            widget.model.availableIntercalls.isNotEmpty
                ? widget.model.availableIntercalls
                : fallbackIntercallChoices,
          );
          final requiredIntercall = structure == GlassStructure.double
              ? widget.model.suggestedIntercallThicknessForDoubleGlass(
            thicknessOuter: spec.thicknessOuter ?? 4.0,
            thicknessInner: spec.thicknessInner ?? 4.0,
          )
              : null;
          // Keep every spacer from the catalogue visible. The suggested
          // spacer is selected automatically, but a deliberate manual
          // selection remains possible after a compatibility warning.
          if (requiredIntercall != null &&
              !intercallChoices.any(
                    (item) =>
                (item['thickness'] as num?)?.toInt() == requiredIntercall,
              )) {
            // A valid spacer may be absent from the catalogue list (for
            // example 9 mm for a 19 mm parclose). Keep the compatible size
            // visible, while the price warning still tells the user to price
            // it in the catalogue before confirming the order.
            intercallChoices.add({
              'thickness': requiredIntercall,
              'name': '$requiredIntercall مم',
            });
          }

          Widget buildProcessingChip(String label,
              GlassProcessing type,
              bool isOuter,
              void Function(GlassProcessing) onTap,) {
            final currentProc = isOuter
                ? spec.processingOuter
                : spec.processingInner;
            final effectiveProc = currentProc == GlassProcessing.tempered
                ? GlassProcessing.none
                : currentProc;
            final selected = effectiveProc == type;
            return FilterChip(
              label: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Colors.white
                      : (selected ? Colors.blue.shade900 : Colors.black87),
                ),
              ),
              selected: selected,
              backgroundColor: isDark ? const Color(0xFF2E2E3E) : null,
              selectedColor: isDark
                  ? Colors.blue.shade900.withValues(alpha: 0.5)
                  : Colors.blue.shade100,
              checkmarkColor: isDark ? Colors.white : Colors.blue.shade900,
              onSelected: (_) => onTap(type),
            );
          }

          Widget buildGlassLayer(bool isOuter) {
            final finish = isOuter ? spec.finishOuter : spec.finishInner;
            final color = isOuter ? spec.colorOuter : spec.colorInner;

            final isTempered = isOuter
                ? (spec.temperedOuter ||
                spec.processingOuter == GlassProcessing.tempered)
                : (spec.temperedInner ||
                spec.processingInner == GlassProcessing.tempered);

            void updateProcessing(GlassProcessing t) {
              final newSpec = spec.copyWith(
                processingOuter: isOuter ? t : null,
                processingInner: !isOuter ? t : null,
              );
              if (zone != null) {
                widget.model.updateSelectedZoneGlass(
                  processingOuter: isOuter ? t : null,
                  processingInner: !isOuter ? t : null,
                );
              } else {
                setState(() {
                  _tempGlassSpec = newSpec;
                });
              }
              _startPaintbrushMode(glassSpec: newSpec);
            }

            void updateTempered(bool val) {
              final legacyOuter =
                  isOuter && spec.processingOuter == GlassProcessing.tempered;
              final legacyInner =
                  !isOuter && spec.processingInner == GlassProcessing.tempered;

              final newSpec = spec.copyWith(
                processingOuter: legacyOuter ? GlassProcessing.none : null,
                processingInner: legacyInner ? GlassProcessing.none : null,
                temperedOuter: isOuter ? val : null,
                temperedInner: !isOuter ? val : null,
              );
              if (zone != null) {
                widget.model.updateSelectedZoneGlass(
                  processingOuter: legacyOuter ? GlassProcessing.none : null,
                  processingInner: legacyInner ? GlassProcessing.none : null,
                  temperedOuter: isOuter ? val : null,
                  temperedInner: !isOuter ? val : null,
                );
              } else {
                setState(() {
                  _tempGlassSpec = newSpec;
                });
              }
              _startPaintbrushMode(glassSpec: newSpec);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    'نوع المعالجة:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    buildProcessingChip(
                      "Simple",
                      GlassProcessing.none,
                      isOuter,
                          (t) => updateProcessing(t),
                    ),
                    buildProcessingChip(
                      "Feuillette",
                      GlassProcessing.laminated,
                      isOuter,
                          (t) => updateProcessing(t),
                    ),
                    buildProcessingChip(
                      "Low-e",
                      GlassProcessing.lowE,
                      isOuter,
                          (t) => updateProcessing(t),
                    ),
                    FilterChip(
                      label: Text(
                        "Trempé",
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white
                              : (isTempered
                              ? Colors.blue.shade900
                              : Colors.black87),
                        ),
                      ),
                      selected: isTempered,
                      backgroundColor: isDark ? const Color(0xFF2E2E3E) : null,
                      selectedColor: isDark
                          ? Colors.blue.shade900.withValues(alpha: 0.5)
                          : Colors.blue.shade100,
                      checkmarkColor: isDark
                          ? Colors.white
                          : Colors.blue.shade900,
                      onSelected: (val) {
                        updateTempered(val);
                      },
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    'المظهر:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children:
                  [
                    GlassFinish.clair,
                    GlassFinish.stopSol,
                    GlassFinish.sable,
                    GlassFinish.delta,
                    GlassFinish.tuC,
                    GlassFinish.nevada,
                    GlassFinish.cuisine,
                    GlassFinish.aFleur,
                  ]
                      .map(
                        (f) =>
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _ContentButton(
                            label: _getFinishName(f),
                            icon: Icons.blur_on_rounded,
                            selected: finish == f,
                            showWarning:
                            widget.model.getPriceForFinish(
                              f,
                              color,
                            ) ==
                                0.0,
                            onPressed: () {
                              double defThick = widget.model
                                  .getThicknessForFinish(
                                f,
                                isOuter
                                    ? spec.colorOuter
                                    : spec.colorInner,
                              );
                              if (defThick == 0.0) defThick = 5.0;

                              final newSpec = fitDoubleGlassToParclose(
                                spec.copyWith(
                                  finishOuter: isOuter ? f : null,
                                  finishInner: !isOuter ? f : null,
                                  thicknessOuter: isOuter
                                      ? defThick
                                      : null,
                                  thicknessInner: !isOuter
                                      ? defThick
                                      : null,
                                ),
                              );
                              if (zone != null) {
                                widget.model.updateSelectedZoneGlass(
                                  finishOuter: isOuter ? f : null,
                                  finishInner: !isOuter ? f : null,
                                  thicknessOuter: isOuter
                                      ? defThick
                                      : null,
                                  thicknessInner: !isOuter
                                      ? defThick
                                      : null,
                                );
                              } else {
                                setState(() {
                                  _tempGlassSpec = newSpec;
                                });
                              }
                              _startPaintbrushMode(glassSpec: newSpec);
                              if (f == GlassFinish.stopSol) {
                                _autoScrollDrawer();
                              }
                            },
                          ),
                        ),
                  )
                      .toList(),

                ),
                if (finish == GlassFinish.stopSol) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      'لون الزجاج (ستوبسول):',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: GlassColor.values
                            .map(
                              (c) =>
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _ContentButton(
                                  label: _getColorName(c),
                                  icon: Icons.palette_rounded,
                                  selected: color == c,
                                  showWarning:
                                  widget.model.getPriceForFinish(
                                    finish,
                                    c,
                                  ) ==
                                      0.0,
                                  onPressed: () {
                                    final double defThick = widget.model
                                        .getThicknessForFinish(
                                      isOuter
                                          ? spec.finishOuter
                                          : spec.finishInner,
                                      c,
                                    );
                                    double resolvedThick = defThick == 0.0
                                        ? 5.0
                                        : defThick;

                                    final newSpec =
                                    fitDoubleGlassToParclose(
                                      spec.copyWith(
                                        colorOuter: isOuter ? c : null,
                                        colorInner: !isOuter ? c : null,
                                        thicknessOuter: isOuter
                                            ? resolvedThick
                                            : null,
                                        thicknessInner: !isOuter
                                            ? resolvedThick
                                            : null,
                                      ),
                                    );
                                    if (zone != null) {
                                      widget.model.updateSelectedZoneGlass(
                                        colorOuter: isOuter ? c : null,
                                        colorInner: !isOuter ? c : null,
                                        thicknessOuter: isOuter
                                            ? resolvedThick
                                            : null,
                                        thicknessInner: !isOuter
                                            ? resolvedThick
                                            : null,
                                      );
                                    } else {
                                      setState(() {
                                        _tempGlassSpec = newSpec;
                                      });
                                    }
                                    _startPaintbrushMode(glassSpec: newSpec);
                                    _autoScrollDrawer();
                                  },
                                ),
                              ),
                        )
                            .toList(),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    Localization.translate('سمك الزجاج:', lang),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                Builder(
                  builder: (context) {
                    var thicknesses = widget.model.getAvailableThicknesses(
                      finish,
                      color,
                    );
                    final String sName =
                        widget.model.activeSlidingSeries?.name.toLowerCase() ??
                            widget.model.activeSeries?.name.toLowerCase() ??
                            '';
                    final isTPR67000 =
                        sName.contains('67000') ||
                            sName.contains('tpr') ||
                            sName.contains('tpi');
                    final isSliding =
                        widget.systemMode == 'sliding' ||
                            widget.model.systemMode == 'sliding';
                    if (isSliding && isTPR67000) {
                      final double minGasket = spec.jointTwoSides ? 4.0 : 2.0;
                      final double maxAllowed =
                          24.0 - minGasket; // 20.0 or 22.0
                      if (spec.structure == GlassStructure.double) {
                        final double tOther = isOuter
                            ? (spec.thicknessInner ?? 4.0)
                            : (spec.thicknessOuter ?? 4.0);
                        final int intercall = spec.intercallThickness;
                        thicknesses = thicknesses
                            .where(
                              (thick) =>
                          (thick + intercall + tOther) <= maxAllowed,
                        )
                            .toList();
                      } else {
                        thicknesses = thicknesses
                            .where((thick) => thick <= maxAllowed)
                            .toList();
                      }
                    }
                    final double currentThickness = isOuter
                        ? (spec.thicknessOuter ??
                        widget.model.getThicknessForFinish(finish, color))
                        : (spec.thicknessInner ??
                        widget.model.getThicknessForFinish(
                          finish,
                          color,
                        ));

                    return _HorizontalWheelScrollArea(
                      builder: (context, controller) =>
                          SingleChildScrollView(
                            controller: controller,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: thicknesses.map((thickVal) {
                                final isSelected = currentThickness == thickVal;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _ContentButton(
                                    label: '${thickVal.toStringAsFixed(0)} مم',
                                    icon: Icons.line_weight_rounded,
                                    selected: isSelected,
                                    onPressed: () {
                                      final newSpec = fitDoubleGlassToParclose(
                                        spec.copyWith(
                                          thicknessOuter: isOuter
                                              ? thickVal
                                              : null,
                                          thicknessInner: !isOuter
                                              ? thickVal
                                              : null,
                                        ),
                                      );
                                      if (zone != null) {
                                        widget.model.updateSelectedZoneGlass(
                                          thicknessOuter: isOuter
                                              ? thickVal
                                              : null,
                                          thicknessInner: !isOuter
                                              ? thickVal
                                              : null,
                                        );
                                      } else {
                                        setState(() {
                                          _tempGlassSpec = newSpec;
                                        });
                                      }
                                      _startPaintbrushMode(glassSpec: newSpec);
                                      _autoScrollDrawer();
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                    );
                  },
                ),
              ],
            );
          }

          return ListView(
            controller: _leftDrawerScrollController,
            padding: const EdgeInsets.all(12.0),
            children: [
              Row(
                children: [
                  Icon(
                    Icons.settings_outlined,
                    color: Colors.blue.shade800,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'خصائص الزجاج',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const Divider(),
              if (parcloseThicknessInfo != null) parcloseThicknessInfo,
              if (targetZone != null &&
                  targetZone.content == ZoneContent.doubleSash) ...[
                Row(
                  children: [
                    Icon(
                      Icons.splitscreen_outlined,
                      color: isDark
                          ? Colors.blue.shade300
                          : Colors.blue.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'نسبة تقسيم الضلفة (ضلفة أكبر من ضلفة)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Card(
                  color: isDark
                      ? const Color(0xFF1E1E2C)
                      : Colors.blue.shade50.withValues(alpha: 0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isDark
                          ? Colors.blue.shade400
                          : Colors.blue.shade100,
                      width: isDark ? 1.5 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'اليسرى: ${(targetZone.doubleSashRatio * 100)
                                  .toInt()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Text(
                              'اليمنى: ${((1.0 - targetZone.doubleSashRatio) *
                                  100).toInt()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: targetZone.doubleSashRatio,
                          min: 0.15,
                          max: 0.85,
                          divisions: 70,
                          label:
                          '${(targetZone.doubleSashRatio * 100).toInt()}%',
                          onChanged: (val) {
                            widget.model.updateZoneDoubleSashRatio(
                              targetZone!.id,
                              val,
                            );
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.blue.shade400
                                      : Colors.blue.shade100,
                                ),
                                foregroundColor: isDark
                                    ? Colors.blue.shade200
                                    : Colors.blue.shade800,
                              ),
                              onPressed: () {
                                widget.model.updateZoneDoubleSashRatio(
                                  targetZone!.id,
                                  0.5,
                                );
                              },
                              child: const Text(
                                'متساويين (50%)',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
                            final double totalWidth =
                                targetZone!.boundary.width;
                            final currentLeftWidth =
                            (targetZone.doubleSashRatio * totalWidth)
                                .toInt();
                            if (!_leftSashFocusNode.hasFocus) {
                              _leftSashWidthController.text = currentLeftWidth
                                  .toString();
                            }

                            void applySashWidth() {
                              final valStr = _leftSashWidthController.text
                                  .trim();
                              final val = double.tryParse(valStr);
                              if (val == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'يرجى إدخال قياس صحيح بالمليمتر',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              final double maxVal = totalWidth * 0.8;
                              if (val > maxVal) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'القياس لا يمكن أن يتجاوز 80% من مجموع عرض الضلفات (${maxVal
                                          .toInt()} مم)',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              final double minVal = totalWidth * 0.15;
                              if (val < minVal) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'القياس لا يمكن أن يقل عن 15% من مجموع عرض الضلفات (${minVal
                                          .toInt()} مم)',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              final double ratio = val / totalWidth;
                              widget.model.updateZoneDoubleSashRatio(
                                targetZone!.id,
                                ratio.clamp(0.15, 0.85),
                              );
                              _leftSashFocusNode.unfocus();
                            }

                            return Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: _leftSashWidthController,
                                      focusNode: _leftSashFocusNode,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'عرض الضلفة اليسرى (مم)',
                                        labelStyle: TextStyle(
                                          fontSize: 10,
                                          color: isDark ? Colors.white70 : null,
                                        ),
                                        contentPadding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? Colors.white30
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? Colors.blue.shade400
                                                : Colors.blue,
                                          ),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                      onSubmitted: (_) => applySashWidth(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: applySashWidth,
                                  child: const Text(
                                    'تطبيق',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
              ],

              // ===== خيار اتجاه الجوان للنظام المنزلق فقط =====
              if (widget.systemMode == 'sliding' ||
                  widget.model.systemMode == 'sliding') ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.compare_arrows_rounded,
                        color: Colors.teal,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'وضع الجوان (منزلق):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'جهتان = جوانان ساقيان   |   جهة واحدة = جوان واحد',
                              style: TextStyle(fontSize: 9, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ToggleButtons(
                        isSelected: [spec.jointTwoSides, !spec.jointTwoSides],
                        borderRadius: BorderRadius.circular(8),
                        selectedColor: Colors.white,
                        fillColor: Colors.teal,
                        textStyle: const TextStyle(fontSize: 11),
                        constraints: const BoxConstraints(
                          minHeight: 30,
                          minWidth: 60,
                        ),
                        onPressed: (idx) {
                          final twoSides = idx == 0;
                          final double tOuter = spec.thicknessOuter ?? 4.0;
                          final double tInner = spec.thicknessInner ?? 4.0;
                          final int intercall = spec.intercallThickness;
                          final bool isValid =
                          spec.structure == GlassStructure.double
                              ? isDoubleGlassValid(
                            tOuter,
                            intercall,
                            tInner,
                            twoSides,
                            widget.model,
                            widget.systemMode,
                          )
                              : isGlassThicknessValid(
                            tOuter,
                            spec.copyWith(jointTwoSides: twoSides),
                            widget.model,
                            widget.systemMode,
                          );

                          if (!isValid) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'لا يمكن التغيير إلى جهتين لأن سمك الزجاج الحالي يتجاوز 20 مم. يرجى تقليل سمك الزجاج أو الفاصل أولاً.',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          final newSpec = spec.copyWith(
                            jointTwoSides: twoSides,
                          );
                          if (zone != null) {
                            widget.model.updateSelectedZoneGlassDecor(
                              jointTwoSides: twoSides,
                            );
                          } else {
                            setState(() => _tempGlassSpec = newSpec);
                          }
                          _startPaintbrushMode(glassSpec: newSpec);
                        },
                        children: const [Text('جهتان'), Text('جهة واحدة')],
                      ),
                    ],
                  ),
                ),
              ],

              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  'هيكل الزجاج:',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _HorizontalWheelScrollArea(
                builder: (context, controller) =>
                    SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: GlassStructure.values
                            .map(
                              (s) =>
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _ContentButton(
                                  label: _getStructureName(s),
                                  icon: Icons.layers_rounded,
                                  selected: structure == s,
                                  onPressed: () {
                                    String? defaultSubtype;
                                    String? defaultColor;
                                    if (s == GlassStructure.closed) {
                                      final panneaux = widget.model
                                          .allGlassCache
                                          .where(
                                            (g) =>
                                        g['type'].toString().toLowerCase() ==
                                            'panneau',
                                      )
                                          .toList();
                                      final subtypes = panneaux
                                          .map((g) =>
                                          (g['subtype'] ?? '').toString())
                                          .where((s) => s.isNotEmpty)
                                          .toSet()
                                          .toList();
                                      if (subtypes.isNotEmpty) {
                                        defaultSubtype =
                                            spec.panneauSubtype ??
                                                subtypes.first;
                                        final subRows = panneaux
                                            .where(
                                              (g) =>
                                          (g['subtype'] ?? '')
                                              .toString()
                                              .toLowerCase() ==
                                              defaultSubtype!.toLowerCase(),
                                        )
                                            .toList();
                                        if (subRows.isNotEmpty) {
                                          final colorsList = subRows
                                              .map(
                                                (g) =>
                                                (g['color'] ?? '')
                                                    .toString()
                                                    .trim(),
                                          )
                                              .where((c) => c.isNotEmpty)
                                              .toSet()
                                              .toList();
                                          if (colorsList.isNotEmpty) {
                                            defaultColor =
                                                spec.panneauColor ??
                                                    colorsList.first;
                                          }
                                        }
                                      }
                                    }

                                    double? defaultThickOuter;
                                    double? defaultThickInner;
                                    if (s == GlassStructure.double) {
                                      defaultThickOuter =
                                          spec.thicknessOuter ??
                                              widget.model
                                                  .getThicknessForFinish(
                                                spec.finishOuter,
                                                spec.colorOuter,
                                              );
                                      defaultThickInner =
                                          spec.thicknessInner ??
                                              widget.model
                                                  .getThicknessForFinish(
                                                spec.finishInner,
                                                spec.colorInner,
                                              );
                                      if (defaultThickOuter == 0.0)
                                        defaultThickOuter = 5.0;
                                      if (defaultThickInner == 0.0)
                                        defaultThickInner = 5.0;
                                    } else if (s == GlassStructure.simple) {
                                      defaultThickOuter =
                                          spec.thicknessOuter ??
                                              widget.model
                                                  .getThicknessForFinish(
                                                spec.finishOuter,
                                                spec.colorOuter,
                                              );
                                      if (defaultThickOuter == 0.0)
                                        defaultThickOuter = 5.0;
                                    }

                                    final newSpec = fitDoubleGlassToParclose(
                                      spec.copyWith(
                                        structure: s,
                                        hasGas: s == GlassStructure.double &&
                                            spec.structure !=
                                                GlassStructure.double
                                            ? true
                                            : null,
                                        panneauSubtype: defaultSubtype,
                                        panneauColor: defaultColor,
                                        thicknessOuter: defaultThickOuter,
                                        thicknessInner: defaultThickInner,
                                      ),
                                    );
                                    if (zone != null) {
                                      widget.model.updateSelectedZoneGlass(
                                        structure: s,
                                        hasGas: s == GlassStructure.double &&
                                            spec.structure !=
                                                GlassStructure.double
                                            ? true
                                            : null,
                                        panneauSubtype: defaultSubtype,
                                        panneauColor: defaultColor,
                                        thicknessOuter: defaultThickOuter,
                                        thicknessInner: defaultThickInner,
                                      );
                                    } else {
                                      setState(() {
                                        _tempGlassSpec = newSpec;
                                      });
                                    }
                                    _startPaintbrushMode(glassSpec: newSpec);
                                    if (s == GlassStructure.double) {
                                      _autoScrollDrawer();
                                    }
                                  },
                                ),
                              ),
                        )
                            .toList(),
                      ),
                    ),
              ),
              const SizedBox(height: 8),
              if (structure == GlassStructure.closed) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    'المظهر (بانو):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                Builder(
                  builder: (context) {
                    final panneaux = widget.model.allGlassCache
                        .where(
                          (g) =>
                      g['type'].toString().toLowerCase() == 'panneau',
                    )
                        .toList();
                    final subtypes = panneaux
                        .map((g) => (g['subtype'] ?? '').toString())
                        .where((s) => s.isNotEmpty)
                        .toSet()
                        .toList();

                    // دائماً نضيف البارداج كخيار ثابت (بروفيل يُحسب بالمتر الطولي)
                    const String bardageKey = 'bardage';
                    if (!subtypes.any(
                          (s) => s.toLowerCase().contains('bardage'),
                    )) {
                      subtypes.add(bardageKey);
                    }

                    String getArabicSubtypeName(String sub) {
                      final s = sub.toLowerCase();
                      if (s.contains('resine') ||
                          s.contains('ارزين') ||
                          s.contains('أرزين'))
                        return 'ارزين';
                      if (s.contains('plexi')) return 'بليكسي';
                      if (s.contains('decore') || s.contains('ديكور'))
                        return 'بانو ديكور';
                      if (s.contains('sandwitch') ||
                          s.contains('sandwich') ||
                          s == 'panneau' ||
                          s == 'بانو')
                        return 'بانو';
                      if (s.contains('aluco') || s.contains('الوكو'))
                        return 'الوكو';
                      if (s.contains('bardage') || s.contains('بارداش'))
                        return 'بارداش';
                      return sub;
                    }

                    IconData getSubtypeIcon(String sub) {
                      final s = sub.toLowerCase();
                      if (s.contains('bardage'))
                        return Icons.view_stream_rounded;
                      return Icons.blur_on_rounded;
                    }

                    final activeSub =
                        spec.panneauSubtype ??
                            (subtypes.isNotEmpty ? subtypes.first : '');

                    return _HorizontalWheelScrollArea(
                      builder: (context, controller) =>
                          SingleChildScrollView(
                            controller: controller,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: subtypes.map((sub) {
                                final isSelected =
                                    (spec.panneauSubtype ?? '').toLowerCase() ==
                                        sub.toLowerCase();
                                final isBardage = sub.toLowerCase().contains(
                                  'bardage',
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _ContentButton(
                                    label: getArabicSubtypeName(sub),
                                    icon: getSubtypeIcon(sub),
                                    selected: isSelected,
                                    onPressed: () {
                                      final subRows = panneaux
                                          .where(
                                            (g) =>
                                        (g['subtype'] ?? '')
                                            .toString()
                                            .toLowerCase() ==
                                            sub.toLowerCase(),
                                      )
                                          .toList();
                                      String firstColor = isBardage
                                          ? 'رمادي'
                                          : 'أبيض';
                                      if (subRows.isNotEmpty) {
                                        final colorsList = subRows
                                            .map(
                                              (g) =>
                                              (g['color'] ?? '')
                                                  .toString()
                                                  .trim(),
                                        )
                                            .where((c) => c.isNotEmpty)
                                            .toSet()
                                            .toList();
                                        if (colorsList.isNotEmpty) {
                                          firstColor = colorsList.first;
                                        }
                                      }

                                      final sLower = sub.toLowerCase();
                                      final GlassFinish targetFinish;
                                      if (isBardage) {
                                        targetFinish = GlassFinish.bardage;
                                      } else if (sLower.contains('resine') ||
                                          sLower.contains('ارزين') ||
                                          sLower.contains('أرزين')) {
                                        targetFinish = GlassFinish.resine;
                                      } else if (sLower.contains('plexi') ||
                                          sLower.contains('بليكسي')) {
                                        targetFinish = GlassFinish.plexyGlass;
                                      } else if (sLower.contains('decor') ||
                                          sLower.contains('ديكور')) {
                                        targetFinish =
                                            GlassFinish.paneauSandwitchDecore;
                                      } else {
                                        targetFinish =
                                            GlassFinish.paneauSandwitch;
                                      }

                                      final newSpec = spec.copyWith(
                                        panneauSubtype: sub,
                                        panneauColor: firstColor,
                                        structure: GlassStructure.closed,
                                        finishOuter: targetFinish,
                                        finishInner: targetFinish,
                                      );
                                      if (zone != null) {
                                        widget.model.updateSelectedZoneGlass(
                                          panneauSubtype: sub,
                                          panneauColor: firstColor,
                                          finishOuter: targetFinish,
                                          finishInner: targetFinish,
                                          structure: GlassStructure.closed,
                                        );
                                      } else {
                                        setState(() {
                                          _tempGlassSpec = newSpec;
                                        });
                                      }
                                      _startPaintbrushMode(glassSpec: newSpec);
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                    );
                  },
                ),
                // ألوان البانو — تُخفى عند اختيار البارداج لأنه بروفيل بلا ألوان
                if (!(spec.panneauSubtype ?? '').toLowerCase().contains(
                  'bardage',
                )) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      'لون البانو:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final panneaux = widget.model.allGlassCache
                          .where(
                            (g) =>
                        g['type'].toString().toLowerCase() == 'panneau',
                      )
                          .toList();
                      final activeSub = spec.panneauSubtype ?? '';
                      final subRows = panneaux
                          .where(
                            (g) =>
                        (g['subtype'] ?? '').toString().toLowerCase() ==
                            activeSub.toLowerCase(),
                      )
                          .toList();
                      List<String> allowedColors = [];
                      if (subRows.isNotEmpty) {
                        allowedColors = subRows
                            .map((g) => (g['color'] ?? '').toString().trim())
                            .where((c) => c.isNotEmpty)
                            .toSet()
                            .toList();
                      }
                      if (allowedColors.isEmpty) {
                        allowedColors = ['أبيض', 'بني', 'بيج', 'رمادي', 'أسود'];
                      }

                      return _HorizontalWheelScrollArea(
                        builder: (context, controller) =>
                            SingleChildScrollView(
                              controller: controller,
                              scrollDirection: Axis.horizontal,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4),
                                child: Row(
                                  children: allowedColors.map((colorName) {
                                    final isSelected =
                                        (spec.panneauColor ?? '')
                                            .toLowerCase() ==
                                            colorName.toLowerCase();
                                    final fakeDbColor = {'name': colorName};
                                    final woodImage = _getWoodTextureImage(
                                      fakeDbColor,
                                    );
                                    final parsedColor = getEffectiveGradientColors(
                                      FrameColor.white,
                                      fakeDbColor,
                                    )[1];

                                    return Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: GestureDetector(
                                        onTap: () {
                                          final newSpec = spec.copyWith(
                                            panneauColor: colorName,
                                          );
                                          if (zone != null) {
                                            widget.model
                                                .updateSelectedZoneGlass(
                                              panneauColor: colorName,
                                            );
                                          } else {
                                            setState(() {
                                              _tempGlassSpec = newSpec;
                                            });
                                          }
                                          _startPaintbrushMode(
                                              glassSpec: newSpec);
                                        },
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: isSelected ? 34 : 28,
                                              height: isSelected ? 34 : 28,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: woodImage != null
                                                    ? null
                                                    : parsedColor,
                                                image: woodImage,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? Colors.blue
                                                      : Colors.grey.shade400,
                                                  width: isSelected ? 2.5 : 1.0,
                                                ),
                                                boxShadow: [
                                                  if (isSelected)
                                                    BoxShadow(
                                                      color: Colors.blue
                                                          .withValues(
                                                        alpha: 0.3,
                                                      ),
                                                      blurRadius: 4,
                                                      spreadRadius: 1,
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              colorName,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isSelected
                                                    ? Colors.blue.shade900
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                      );
                    },
                  ),
                ] else
                  ...[
                    // اختيار مقاس البارداج المتوفر في قاعدة البيانات
                    const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 6),
                      child: Text(
                        'مقاس وسماكة البارداج:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        // 1. نبحث أولاً في بروفيلات السيستم/السلسلة الحالية عن قطاع بارداج
                        final bardageSections =
                        (activeSeriesForSystem?.sections ?? []).where((s) {
                          final t = s.type.toLowerCase().trim();
                          final n = s.name.toLowerCase().trim();
                          return t == 'bardage' ||
                              t.contains('bardage') ||
                              t.contains('بارداج') ||
                              t.contains('بارداش') ||
                              n.contains('bardage') ||
                              n.contains('بارداج') ||
                              n.contains('بارداش');
                        }).toList();

                        final List<Map<String, dynamic>> productsList = [];
                        bool isProfileSection = false;

                        if (bardageSections.isNotEmpty) {
                          isProfileSection = true;
                          for (var s in bardageSections) {
                            productsList.add({
                              'id': s.id,
                              'name': s.name,
                              'code': s.code,
                              'thickness': s.thickness,
                              'visible_width': s.visibleWidth > 0
                                  ? s.visibleWidth
                                  : 100.0,
                              'bar_length': s.barLength,
                              'is_profile': true,
                            });
                          }
                        } else {
                          // 2. الاحتياط: البحث في جدول Glass كما في السابق
                          final bardageProducts = widget.model.allGlassCache
                              .where(
                                (g) =>
                            g['type'].toString().toLowerCase() ==
                                'panneau' &&
                                (g['subtype'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .contains('bardage'),
                          )
                              .toList();

                          final Map<int, Map<String, dynamic>> uniqueProducts =
                          {};
                          for (var p in bardageProducts) {
                            final id = p['id'] as int?;
                            if (id != null) {
                              uniqueProducts[id] = p;
                            }
                          }
                          productsList.addAll(uniqueProducts.values);
                        }

                        final int? currentProductId =
                            spec.panneauProductId ??
                                (productsList.isNotEmpty
                                    ? productsList.first['id'] as int?
                                    : null);

                        if (productsList.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade100),
                            ),
                            child: const Text(
                              'لم يتم العثور على منتجات بارداج في قاعدة البيانات. سيتم استخدام المقاس الافتراضي (100 مم / سمك 24 مم).',
                              style: TextStyle(fontSize: 9, color: Colors.red),
                            ),
                          );
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: currentProductId,
                              isExpanded: true,
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: Colors.blue,
                              ),
                              items: productsList.map((p) {
                                final name = p['name']?.toString() ?? 'بارداج';
                                final double dbVw =
                                    (p['visible_width'] as num?)?.toDouble() ??
                                        0.0;
                                final double dbThick =
                                    (p['thickness'] as num?)?.toDouble() ??
                                        24.0;
                                final double visibleW = dbVw > 0
                                    ? dbVw
                                    : dbThick;
                                final double thickness = dbThick;
                                return DropdownMenuItem<int>(
                                  value: p['id'] as int?,
                                  child: Text(
                                    '$name - العرض: ${visibleW.toStringAsFixed(
                                        0)} مم (السمك: ${thickness
                                        .toStringAsFixed(0)} مم)',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) async {
                                if (val != null) {
                                  final chosen = productsList.firstWhere(
                                        (p) => p['id'] == val,
                                  );
                                  final newSpec = spec.copyWith(
                                    panneauProductId: val,
                                  );

                                  if (chosen['is_profile'] == true) {
                                    final mutableChosen =
                                    Map<String, dynamic>.from(chosen);
                                    final dbInstance = SqlDatabase();
                                    final colorId =
                                    widget.model.selectedDbColor?['id'];
                                    double price = await dbInstance
                                        .getSectionPrice(val, colorId);
                                    if (price <= 0) {
                                      price =
                                          ((mutableChosen['price_dzd'] ??
                                              mutableChosen['price'] ??
                                              0.0)
                                          as num)
                                              .toDouble();
                                    }
                                    mutableChosen['calculated_price'] = price;
                                    widget
                                        .model
                                        .componentOverrides['البارداج (Bardage)'] =
                                        mutableChosen;
                                  } else {
                                    widget.model.componentOverrides.remove(
                                      'البارداج (Bardage)',
                                    );
                                  }

                                  if (zone != null) {
                                    widget.model.updateSelectedZoneGlass(
                                      panneauProductId: val,
                                    );
                                  } else {
                                    setState(() {
                                      _tempGlassSpec = newSpec;
                                    });
                                  }
                                  _startPaintbrushMode(glassSpec: newSpec);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // البارداج يأخذ ألوان البروفيلات (السيري)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        'لون البارداج:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final profileColors = widget.model.availableColors;
                        final colorList = profileColors.isNotEmpty
                            ? profileColors
                            : [
                          {'name': 'أبيض'},
                          {'name': 'بني'},
                          {'name': 'رمادي'},
                          {'name': 'أسود'},
                        ];

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _HorizontalWheelScrollArea(
                              builder: (context, controller) =>
                                  SingleChildScrollView(
                                    controller: controller,
                                    scrollDirection: Axis.horizontal,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Row(
                                        children: colorList.map((colorMap) {
                                          final colorName = (colorMap['name'] ??
                                              '')
                                              .toString();
                                          final isSelected =
                                              (spec.panneauColor ?? '')
                                                  .toLowerCase() ==
                                                  colorName.toLowerCase();
                                          final woodImage = _getWoodTextureImage(
                                            colorMap,
                                          );
                                          final parsedColor =
                                          getEffectiveGradientColors(
                                            FrameColor.white,
                                            colorMap,
                                          )[1];

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                right: 10),
                                            child: GestureDetector(
                                              onTap: () {
                                                final newSpec = spec.copyWith(
                                                  panneauColor: colorName,
                                                );
                                                if (zone != null) {
                                                  widget.model
                                                      .updateSelectedZoneGlass(
                                                    panneauColor: colorName,
                                                  );
                                                } else {
                                                  setState(() {
                                                    _tempGlassSpec = newSpec;
                                                  });
                                                }
                                                _startPaintbrushMode(
                                                  glassSpec: newSpec,
                                                );
                                              },
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: isSelected ? 34 : 28,
                                                    height: isSelected
                                                        ? 34
                                                        : 28,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: woodImage != null
                                                          ? null
                                                          : parsedColor,
                                                      image: woodImage,
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? Colors.blue
                                                            : Colors.grey
                                                            .shade400,
                                                        width: isSelected
                                                            ? 2.5
                                                            : 1.0,
                                                      ),
                                                      boxShadow: [
                                                        if (isSelected)
                                                          BoxShadow(
                                                            color: Colors.blue
                                                                .withOpacity(
                                                                0.3),
                                                            blurRadius: 4,
                                                            spreadRadius: 1,
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  SizedBox(
                                                    width: 42,
                                                    child: Text(
                                                      colorName,
                                                      textAlign: TextAlign
                                                          .center,
                                                      maxLines: 2,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: isSelected
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                        color: isSelected
                                                            ? Colors.blue
                                                            .shade900
                                                            : Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'اتجاه شرائح البارداج:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _ContentButton(
                                    label: 'أفقي',
                                    icon: Icons.reorder_rounded,
                                    selected: !(spec.isVerticalBardage),
                                    onPressed: () {
                                      final newSpec = spec.copyWith(
                                        isVerticalBardage: false,
                                      );
                                      if (zone != null &&
                                          widget.model.activeSubZone != null) {
                                        widget.model.updateSelectedZoneGlass(
                                          isVerticalBardage: false,
                                        );
                                      } else {
                                        setState(() {
                                          _tempGlassSpec = newSpec;
                                        });
                                      }
                                      _startPaintbrushMode(glassSpec: newSpec);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ContentButton(
                                    label: 'عمودي',
                                    icon: Icons.view_week_rounded,
                                    selected: spec.isVerticalBardage,
                                    onPressed: () {
                                      final newSpec = spec.copyWith(
                                        isVerticalBardage: true,
                                      );
                                      if (zone != null &&
                                          widget.model.activeSubZone != null) {
                                        widget.model.updateSelectedZoneGlass(
                                          isVerticalBardage: true,
                                        );
                                      } else {
                                        setState(() {
                                          _tempGlassSpec = newSpec;
                                        });
                                      }
                                      _startPaintbrushMode(glassSpec: newSpec);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.orange.shade200),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.view_stream_rounded,
                                    size: 12,
                                    color: Colors.orange,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'يُحسب بالمتر الطولي كبروفيل',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
              ] else
                if (structure == GlassStructure.double) ...[
                  const Divider(),
                  const Text(
                    "الوجه الخارجي",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                  buildGlassLayer(true),
                  const SizedBox(height: 8),
                  const Divider(),
                  const Text(
                    "الوجه الداخلي",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                  buildGlassLayer(false),
                  const SizedBox(height: 12),
                  const Text(
                    "سمك الفاصل (Intercall) — المقترح تلقائياً حسب Parclose:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (requiredIntercall == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'لا توجد Parclose مناسبة لسماكة لوحي الزجاج المختارة. اختر Parclose مزدوجة متوافقة أولاً.',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: intercallChoices.map((g) {
                      int val = (g['thickness'] as num?)?.toInt() ?? 0;
                      return _IntercallButton(
                        thickness: val,
                        selected: spec.intercallThickness == val,
                        showWarning:
                        widget.model.getPriceForIntercall(val) == 0.0,
                        onPressed: () {
                          final double tOuter =
                              spec.thicknessOuter ?? 4.0;
                          final double tInner =
                              spec.thicknessInner ?? 4.0;
                          String? warning;
                          if (requiredIntercall == null) {
                            warning =
                                'تنبيه: لا توجد Parclose مطابقة تلقائياً لسماكة لوحي الزجاج. تحقق من الطلب قبل اعتماده.';
                          } else if (val != requiredIntercall) {
                            warning =
                                'تنبيه: السماكة المقترحة مع Parclose هي $requiredIntercall مم، وتم اختيار $val مم يدوياً.';
                          }
                          if (!isDoubleGlassValid(
                            tOuter,
                            val,
                            tInner,
                            spec.jointTwoSides,
                            widget.model,
                            widget.systemMode,
                          )) {
                            warning =
                                '${warning == null ? '' : '$warning\n'}تنبيه: سماكة الزجاج المختارة (${tOuter + val + tInner} مم) تتجاوز قيود الجوان في السلسلة.';
                          }
                          final newSpec = spec.copyWith(
                            intercallThickness: val,
                          );
                          if (zone != null) {
                            widget.model.updateSelectedZoneGlass(
                              intercallThickness: val,
                            );
                          } else {
                            setState(() {
                              _tempGlassSpec = newSpec;
                            });
                          }
                          _startPaintbrushMode(glassSpec: newSpec);
                          if (warning != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(warning),
                                backgroundColor: Colors.orange.shade800,
                              ),
                            );
                          }
                        },
                      );
                    }).toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.air_rounded,
                          color: Colors.blue,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'يحتوي على غاز (Gas)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Switch(
                          value: spec.hasGas,
                          activeThumbColor: Colors.blue,
                          onChanged: (val) {
                            final newSpec = spec.copyWith(hasGas: val);
                            if (zone != null) {
                              widget.model.updateSelectedZoneGlass(hasGas: val);
                            } else {
                              setState(() {
                                _tempGlassSpec = newSpec;
                              });
                            }
                            _startPaintbrushMode(glassSpec: newSpec);
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "ديكور الزجاج المزدوج (ورود):",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "وردات",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Checkbox(
                            value: spec.hasRosettes,
                            activeColor: Colors.blue,
                            visualDensity: VisualDensity.compact,
                            onChanged: (val) {
                              if (val != null) {
                                final newSpec = spec.copyWith(hasRosettes: val);
                                if (zone != null) {
                                  widget.model.updateSelectedZoneGlassDecor(
                                    hasRosettes: val,
                                  );
                                } else {
                                  setState(() => _tempGlassSpec = newSpec);
                                }
                                _startPaintbrushMode(glassSpec: newSpec);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('أفقي:', style: TextStyle(fontSize: 12)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        onPressed: () {
                          if (spec.decorH > 0) {
                            final newSpec = spec.copyWith(
                              decorH: spec.decorH - 1,
                            );
                            if (zone != null) {
                              widget.model.updateSelectedZoneGlassDecor(
                                decorH: newSpec.decorH,
                              );
                            } else {
                              setState(() => _tempGlassSpec = newSpec);
                            }
                            _startPaintbrushMode(glassSpec: newSpec);
                          }
                        },
                      ),
                      Text(
                        '${spec.decorH}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        onPressed: () {
                          final newSpec = spec.copyWith(
                              decorH: spec.decorH + 1);
                          if (zone != null) {
                            widget.model.updateSelectedZoneGlassDecor(
                              decorH: newSpec.decorH,
                            );
                          } else {
                            setState(() => _tempGlassSpec = newSpec);
                          }
                          _startPaintbrushMode(glassSpec: newSpec);
                        },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('عمودي:', style: TextStyle(fontSize: 12)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        onPressed: () {
                          if (spec.decorV > 0) {
                            final newSpec = spec.copyWith(
                              decorV: spec.decorV - 1,
                            );
                            if (zone != null) {
                              widget.model.updateSelectedZoneGlassDecor(
                                decorV: newSpec.decorV,
                              );
                            } else {
                              setState(() => _tempGlassSpec = newSpec);
                            }
                            _startPaintbrushMode(glassSpec: newSpec);
                          }
                        },
                      ),
                      Text(
                        '${spec.decorV}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        onPressed: () {
                          final newSpec = spec.copyWith(
                              decorV: spec.decorV + 1);
                          if (zone != null) {
                            widget.model.updateSelectedZoneGlassDecor(
                              decorV: newSpec.decorV,
                            );
                          } else {
                            setState(() => _tempGlassSpec = newSpec);
                          }
                          _startPaintbrushMode(glassSpec: newSpec);
                        },
                      ),
                    ],
                  ),
                  Builder(
                    builder: (context) {
                      final baguettes = widget.model.allGlassCache
                          .where(
                            (g) =>
                            g['type'].toString().toLowerCase().contains(
                              'baguette',
                            ),
                      )
                          .toList();

                      if (baguettes.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'لا يوجد باجيت ديكور في قاعدة البيانات. يرجى إضافتها أولاً.',
                            style: TextStyle(color: Colors.red, fontSize: 11),
                          ),
                        );
                      }

                      // Safe int id extraction
                      int? specBaguetteId = (spec.decorBaguetteId is int)
                          ? spec.decorBaguetteId as int
                          : int.tryParse(spec.decorBaguetteId?.toString() ??
                          '');

                      var selectedBaguette = baguettes.firstWhere(
                            (b) => (b['id'] as num?)?.toInt() == specBaguetteId,
                        orElse: () => baguettes.first,
                      );

                      final int selectedBaguetteId =
                          (selectedBaguette['id'] as num?)?.toInt() ??
                              (baguettes.first['id'] as num?)?.toInt() ??
                              0;

                      List<String> allowedColors = widget.model.allGlassCache
                          .where(
                            (g) =>
                        (g['id'] as num?)?.toInt() == selectedBaguetteId,
                      )
                          .map((g) => g['color']?.toString() ?? '')
                          .where((c) => c.isNotEmpty)
                          .toList();
                      if (allowedColors.isEmpty) {
                        allowedColors = ['أبيض', 'ذهبي', 'فضي', 'رمادي'];
                      }

                      String currentDecorColor = spec.decorColor;
                      if (!allowedColors.contains(currentDecorColor)) {
                        currentDecorColor = allowedColors.first;
                      }

                      // Build unique items lists (no duplicate ids)
                      final List<int> baguetteIds = [];
                      final List<Map<String, dynamic>> uniqueBaguettes = [];
                      for (final b in baguettes) {
                        final id = (b['id'] as num?)?.toInt();
                        if (id != null && !baguetteIds.contains(id)) {
                          baguetteIds.add(id);
                          uniqueBaguettes.add(b);
                        }
                      }

                      // Ensure selected value is in list
                      final int safeSelectedId =
                      baguetteIds.contains(selectedBaguetteId)
                          ? selectedBaguetteId
                          : (baguetteIds.isNotEmpty ? baguetteIds.first : 0);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'نوع الباجيت:',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    isExpanded: true,
                                    value: safeSelectedId,
                                    items: uniqueBaguettes.map((b) {
                                      final id = (b['id'] as num?)?.toInt() ??
                                          0;
                                      return DropdownMenuItem<int>(
                                        value: id,
                                        child: Text(
                                          '${b['name']} (${b['thickness']} مم)',
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        final newBaguette = uniqueBaguettes
                                            .firstWhere(
                                              (b) =>
                                          (b['id'] as num?)?.toInt() ==
                                              val,
                                          orElse: () => uniqueBaguettes.first,
                                        );
                                        final double newThickness =
                                            (newBaguette['thickness'] as num?)
                                                ?.toDouble() ??
                                                0.0;
                                        final allowedColorsList =
                                        (newBaguette['color']?.toString() ??
                                            '')
                                            .split(',')
                                            .map((c) => c.trim())
                                            .where((c) => c.isNotEmpty)
                                            .toList();
                                        final String newColor =
                                        allowedColorsList.isNotEmpty
                                            ? allowedColorsList.first
                                            : 'أبيض';

                                        final newSpec = spec.copyWith(
                                          decorBaguetteId: val,
                                          decorThickness: newThickness,
                                          decorColor: newColor,
                                        );

                                        if (zone != null) {
                                          widget.model
                                              .updateSelectedZoneGlassDecor(
                                            decorBaguetteId: val,
                                            decorThickness: newThickness,
                                            decorColor: newColor,
                                          );
                                        } else {
                                          setState(
                                                () => _tempGlassSpec = newSpec,
                                          );
                                        }
                                        _startPaintbrushMode(
                                            glassSpec: newSpec);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Text(
                                'اللون:',
                                style: TextStyle(fontSize: 12),
                              ),
                              const Spacer(),
                              DropdownButton<String>(
                                value: currentDecorColor,
                                items: allowedColors.map((colorName) {
                                  return DropdownMenuItem<String>(
                                    value: colorName,
                                    child: Text(
                                      colorName,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    final newSpec = spec.copyWith(
                                      decorColor: val,
                                    );
                                    if (zone != null) {
                                      widget.model.updateSelectedZoneGlassDecor(
                                        decorColor: val,
                                      );
                                    } else {
                                      setState(() => _tempGlassSpec = newSpec);
                                    }
                                    _startPaintbrushMode(glassSpec: newSpec);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  if (spec.hasRosettes) ...[
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final rosettes = widget.model.allGlassCache
                            .where(
                              (g) =>
                              g['type'].toString().toLowerCase().contains(
                                'rosette',
                              ),
                        )
                            .toList();

                        if (rosettes.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(
                              'لا يوجد وردات ديكور في قاعدة البيانات. يرجى إضافتها أولاً.',
                              style: TextStyle(color: Colors.red, fontSize: 11),
                            ),
                          );
                        }

                        // Safe int id extraction for rosette
                        int? specRosetteId = (spec.decorRosetteId is int)
                            ? spec.decorRosetteId as int
                            : int.tryParse(
                            spec.decorRosetteId?.toString() ?? '');

                        // Build unique rosette items (no duplicate ids)
                        final List<int> rosetteIds = [];
                        final List<Map<String, dynamic>> uniqueRosettes = [];
                        for (final r in rosettes) {
                          final id = (r['id'] as num?)?.toInt();
                          if (id != null && !rosetteIds.contains(id)) {
                            rosetteIds.add(id);
                            uniqueRosettes.add(r);
                          }
                        }

                        var selectedRosette = uniqueRosettes.firstWhere(
                              (r) =>
                          (r['id'] as num?)?.toInt() == specRosetteId,
                          orElse: () => uniqueRosettes.first,
                        );

                        final int selectedRosetteId =
                            (selectedRosette['id'] as num?)?.toInt() ??
                                (rosetteIds.isNotEmpty ? rosetteIds.first : 0);

                        final int safeRosetteId =
                        rosetteIds.contains(selectedRosetteId)
                            ? selectedRosetteId
                            : (rosetteIds.isNotEmpty ? rosetteIds.first : 0);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'نوع الوردة:',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      isExpanded: true,
                                      value: safeRosetteId,
                                      items: uniqueRosettes.map((r) {
                                        final id =
                                            (r['id'] as num?)?.toInt() ?? 0;
                                        return DropdownMenuItem<int>(
                                          value: id,
                                          child: Text(
                                            r['name'].toString(),
                                            style: const TextStyle(
                                                fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          final newSpec = spec.copyWith(
                                            decorRosetteId: val,
                                          );
                                          if (zone != null) {
                                            widget.model
                                                .updateSelectedZoneGlassDecor(
                                              decorRosetteId: val,
                                            );
                                          } else {
                                            setState(
                                                  () =>
                                              _tempGlassSpec = newSpec,
                                            );
                                          }
                                          _startPaintbrushMode(
                                            glassSpec: newSpec,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  'شكل الوردة:',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      isExpanded: true,
                                      value: spec.rosetteShape,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 1,
                                          child: Text(
                                            'شكل 1 (نجمة)',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 2,
                                          child: Text(
                                            'شكل 2 (منحني)',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 3,
                                          child: Text(
                                            'شكل 3 (باروكي)',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 4,
                                          child: Text(
                                            'شكل 4 (معين مصمت)',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          final newSpec = spec.copyWith(
                                            rosetteShape: val,
                                          );
                                          if (zone != null) {
                                            widget.model
                                                .updateSelectedZoneGlassDecor(
                                              rosetteShape: val,
                                            );
                                          } else {
                                            setState(
                                                  () =>
                                              _tempGlassSpec = newSpec,
                                            );
                                          }
                                          _startPaintbrushMode(
                                            glassSpec: newSpec,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ] else
                  ...[
                    const SizedBox(height: 8),
                    buildGlassLayer(true),
                  ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildDrawerContent(BuildContext context) {
    return ScrollConfiguration(
      behavior: _drawerScrollBehavior(context),
      child: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final lang = Provider
              .of<AppSettingsProvider>(context)
              .language;
          final slidingZones = widget.model.zones
              .where((z) => z.content == ZoneContent.slidingSash)
              .toList();
          final firstSlidingZone = slidingZones.isNotEmpty
              ? slidingZones.first
              : null;
          final int sashesCount = firstSlidingZone?.slidingSashesCount ?? 2;
          int centralCount = (sashesCount - 1) * 2;

          // دالة مساعدة لرسم الـ Checkbox ملتصقاً بنصه
          Widget buildCompactOption(String label, String key, WindowZone zone) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: zone.slidingMontantReinforced[key] ?? false,
                  onChanged: (v) {
                    setState(() {
                      zone.slidingMontantReinforced[key] = v ?? false;
                    });
                    widget.model.refreshUI();
                  },
                  activeColor: Colors.blue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            children: [
              // 🟢 1. الخصائص العامة
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: Colors.blue.shade800),
                  const SizedBox(width: 8),
                  Text(
                    Localization.translate('الخصائص العامة', lang),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),

              TextField(
                controller: _positionCtrl,
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'موقع النافذة (مثال: المطبخ - الطابق 2)',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_on),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (val) {
                  widget.model.position = val;
                },
              ),
              const SizedBox(height: 15),

              GestureDetector(
                onTap: () {
                  widget.model.toggleViewMode();
                  setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: widget.model.isInternalView
                        ? (Theme
                        .of(context)
                        .brightness == Brightness.dark
                        ? Colors.blue.shade900.withValues(alpha: 0.3)
                        : Colors.blue.shade50)
                        : (Theme
                        .of(context)
                        .brightness == Brightness.dark
                        ? Colors.orange.shade900.withValues(alpha: 0.3)
                        : Colors.orange.shade50),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.model.isInternalView
                          ? Colors.blue
                          : Colors.orange,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.model.isInternalView
                            ? Icons.visibility
                            : Icons.flip_camera_android,
                        size: 20,
                        color: widget.model.isInternalView
                            ? (Theme
                            .of(context)
                            .brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue.shade900)
                            : (Theme
                            .of(context)
                            .brightness == Brightness.dark
                            ? Colors.orange.shade300
                            : Colors.orange.shade900),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.model.isInternalView
                            ? Localization.translate('مشاهدة: وجه داخلي', lang)
                            : Localization.translate('مشاهدة: وجه خارجي', lang),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: widget.model.isInternalView
                              ? (Theme
                              .of(context)
                              .brightness == Brightness.dark
                              ? Colors.blue.shade300
                              : Colors.blue.shade900)
                              : (Theme
                              .of(context)
                              .brightness == Brightness.dark
                              ? Colors.orange.shade300
                              : Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                widget.model.selectedDbColor != null
                    ? '${Localization.translate('اللون:', lang)} ${widget.model
                    .selectedDbColor!['name']}'
                    : Localization.translate('لون الألمنيوم', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.model.availableColors.map((dbColor) {
                  final isSelected =
                      widget.model.selectedDbColor != null &&
                          widget.model.selectedDbColor!['id'] == dbColor['id'];
                  Color parsedColor = getEffectiveGradientColors(
                    FrameColor.white,
                    dbColor,
                  )[1];
                  final woodImage = _getWoodTextureImage(dbColor);
                  return GestureDetector(
                    onTap: () {
                      widget.model.selectedDbColor = dbColor;
                      widget.model.refreshUI();
                    },
                    child: Container(
                      width: isSelected ? 30 : 25,
                      height: isSelected ? 30 : 25,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: woodImage != null ? null : parsedColor,
                        image: woodImage,
                        border: Border.all(
                          color: isSelected
                              ? Colors.blue
                              : Colors.grey.shade400,
                          width: isSelected ? 2.5 : 1.0,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 15),

              Text(
                widget.model.selectedAccessoryColor != null
                    ? '${Localization.translate(
                    'لون الإكسسوارات:', lang)} ${widget.model
                    .selectedAccessoryColor!['name']}'
                    : Localization.translate('لون الإكسسوارات (افتراضي)', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.model.availableAccessoryColors.map((dbColor) {
                  final isSelected =
                      widget.model.selectedAccessoryColor != null &&
                          widget.model.selectedAccessoryColor!['id'] ==
                              dbColor['id'];
                  Color parsedColor = getEffectiveGradientColors(
                    FrameColor.white,
                    dbColor,
                  )[1];
                  final woodImage = _getWoodTextureImage(dbColor);
                  return GestureDetector(
                    onTap: () {
                      if (isSelected) {
                        widget.model.selectedAccessoryColor = null;
                      } else {
                        widget.model.selectedAccessoryColor = dbColor;
                      }
                      widget.model.refreshUI();
                    },
                    child: Container(
                      width: isSelected ? 30 : 25,
                      height: isSelected ? 30 : 25,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: woodImage != null ? null : parsedColor,
                        image: woodImage,
                        border: Border.all(
                          color: isSelected
                              ? Colors.blue
                              : Colors.grey.shade400,
                          width: isSelected ? 2.5 : 1.0,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (widget.model.systemMode != 'sliding')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('إطار سفلي', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.hasBottomFrame,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) => widget.model.toggleBottomFrame(value),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  Localization.translate('رسم الجدار', lang),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                value: widget.model.showWall,
                activeColor: Colors.blue,
                onChanged: (value) => widget.model.toggleShowWall(value),
              ),
              if (widget.model.showWall) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'لون الجدار',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          // Red wall color option
                          GestureDetector(
                            onTap: () => widget.model.toggleWallColor('red'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.model.wallColor == 'red'
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: widget.model.wallColor == 'red'
                                      ? Colors.red
                                      : Colors.grey.shade300,
                                  width: widget.model.wallColor == 'red'
                                      ? 2
                                      : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFC85A3F),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'أحمر',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Grey wall color option
                          GestureDetector(
                            onTap: () => widget.model.toggleWallColor('grey'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.model.wallColor == 'grey'
                                    ? Colors.grey.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: widget.model.wallColor == 'grey'
                                      ? Colors.grey.shade700
                                      : Colors.grey.shade300,
                                  width: widget.model.wallColor == 'grey'
                                      ? 2
                                      : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF8A939E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'رمادي 9007',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
              (() {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('غطاء جانبي', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.hasSideCovers,
                  activeColor: Colors.blue,
                  onChanged: (value) => widget.model.toggleSideCovers(value),
                );
              }()),
              if (widget.model.hasSideCovers) ...[
                if ((widget.model
                    .getSectionByType('frame')
                    ?.couvreJointWidth ??
                    0) ==
                    0 &&
                    widget.model.availableSideCovers.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'اختر الغطاء الجانبي',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      value:
                      widget.model.availableSideCovers.any(
                            (c) => c.id == widget.model.selectedSideCover?.id,
                      )
                          ? widget.model.selectedSideCover?.id
                          : widget.model.availableSideCovers.first.id,
                      items: widget.model.availableSideCovers.map((cover) {
                        return DropdownMenuItem<int>(
                          value: cover.id,
                          child: Text(
                            cover.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            widget.model.selectedSideCover = widget
                                .model
                                .availableSideCovers
                                .firstWhere((c) => c.id == val);
                            widget.model.refreshUI();
                          });
                        }
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: buildSideCoverSegmentsControl(
                    context,
                    widget.model,
                    lang,
                  ),
                ),
                // زر تبديل اتجاه الغطاء الجانبي — يظهر فقط إذا كان للمقطع اتجاهان والإطار بدون كفر جو مدمج
                if ((widget.model
                    .getSectionByType('frame')
                    ?.couvreJointWidth ??
                    0) ==
                    0 &&
                    (widget.model.selectedSideCover?.couvreJointWidth ?? 0) >
                        0 &&
                    (widget.model.selectedSideCover?.visibleWidth ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        side: BorderSide(color: Colors.blue.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () =>
                          widget.model.toggleSideCoverOrientation(),
                      icon: Icon(
                        Icons.swap_horiz,
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                      label: Text(
                        widget.model.sideCoverUseSecondWidth
                            ? '${widget.model.selectedSideCover!.visibleWidth
                            .toStringAsFixed(0)} mm'
                            : '${widget.model.selectedSideCover!
                            .couvreJointWidth.toStringAsFixed(0)} mm',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ),
              ],
              (() {
                final isArchedOrSlanted =
                    widget.model.archHeight > 0 ||
                        widget.model.topSlantLeftY != 0 ||
                        widget.model.topSlantRightY != 0;
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('ستار (Volet)', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: isArchedOrSlanted
                      ? Text(
                    Localization.translate(
                      'الستار غير مدعوم للأشكال المقوسة أو المائلة',
                      lang,
                    ),
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                    ),
                  )
                      : null,
                  value: widget.model.hasShutter,
                  activeThumbColor: Colors.blue,
                  onChanged: isArchedOrSlanted
                      ? null
                      : (value) => widget.model.toggleShutter(value),
                );
              }()),

              if (widget.model.hasShutter) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('صندوق نفق (Coffre Tunnel)', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.isCaissonTunnel,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) {
                    widget.model.toggleCaissonTunnel(value);
                  },
                ),
                if (widget.model.isCaissonTunnel) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                    child: Text(
                      Localization.translate(
                        'ارتفاع Caisson Tunnel (Hauteur Tunnel):',
                        lang,
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ContentButton(
                        label: '25 سم',
                        icon: Icons.straighten,
                        selected: widget.model.caissonTunnelHeight == 250.0,
                        onPressed: () {
                          setState(() {
                            widget.model.setCaissonTunnelHeight(250.0);
                          });
                        },
                      ),
                      _ContentButton(
                        label: '30 سم',
                        icon: Icons.straighten,
                        selected: widget.model.caissonTunnelHeight == 300.0,
                        onPressed: () {
                          setState(() {
                            widget.model.setCaissonTunnelHeight(300.0);
                          });
                        },
                      ),
                      _ContentButton(
                        label: '40 سم',
                        icon: Icons.straighten,
                        selected: widget.model.caissonTunnelHeight == 400.0,
                        onPressed: () {
                          setState(() {
                            widget.model.setCaissonTunnelHeight(400.0);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 5),
                  child: Text(
                    Localization.translate('نوع الستار (Mechanism):', lang),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ContentButton(
                      label: 'حزام (Sangle)',
                      icon: Icons.line_weight,
                      selected: widget.model.shutterMechanism == 'حزام',
                      onPressed: () {
                        setState(
                              () => widget.model.shutterMechanism = 'حزام',
                        );
                        widget.model.refreshUI();
                        unawaited(widget.model.updateShutterDefaultsIfNeeded());
                      },
                    ),
                    _ContentButton(
                      label: 'منايفال (Manivelle)',
                      icon: Icons.rotate_right,
                      selected: widget.model.shutterMechanism == 'منايفال',
                      onPressed: () {
                        setState(
                              () => widget.model.shutterMechanism = 'منايفال',
                        );
                        widget.model.refreshUI();
                        unawaited(widget.model.updateShutterDefaultsIfNeeded());
                      },
                    ),
                    _ContentButton(
                      label: 'محرك (Moteur)',
                      icon: Icons.electrical_services,
                      selected: widget.model.shutterMechanism == 'محرك',
                      onPressed: () {
                        setState(
                              () => widget.model.shutterMechanism = 'محرك',
                        );
                        widget.model.refreshUI();
                        unawaited(widget.model.updateShutterDefaultsIfNeeded());
                      },
                    ),
                  ],
                ),

                if (widget.model.shutterMechanism == 'محرك') ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 10, bottom: 5),
                    child: Text(
                      'خيارات المحرك:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ContentButton(
                        label: 'قاطعة (Interrupteur)',
                        icon: Icons.power,
                        selected: widget.model.motorHasInterrupteur,
                        onPressed: () {
                          setState(() {
                            widget.model.motorHasInterrupteur =
                            !widget.model.motorHasInterrupteur;
                            widget.model.refreshUI();
                          });
                        },
                      ),
                      _ContentButton(
                        label: 'جهاز تحكم (Télécommande)',
                        icon: Icons.settings_remote,
                        selected: widget.model.motorHasTelecommande,
                        onPressed: () {
                          setState(() {
                            widget.model.motorHasTelecommande =
                            !widget.model.motorHasTelecommande;
                            widget.model.refreshUI();
                          });
                        },
                      ),
                    ],
                  ),
                ],

                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 5),
                  child: Text(
                    Localization.translate('جهة الستار (Drive Side):', lang),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ContentButton(
                      label: 'يمين (Droite)',
                      icon: Icons.keyboard_double_arrow_right,
                      selected: widget.model.shutterDriveSide == 'right',
                      onPressed: () {
                        setState(
                              () => widget.model.shutterDriveSide = 'right',
                        );
                        widget.model.refreshUI();
                      },
                    ),
                    _ContentButton(
                      label: 'يسار (Gauche)',
                      icon: Icons.keyboard_double_arrow_left,
                      selected: widget.model.shutterDriveSide == 'left',
                      onPressed: () {
                        setState(
                              () => widget.model.shutterDriveSide = 'left',
                        );
                        widget.model.refreshUI();
                      },
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 5),
                  child: Text(
                    Localization.translate('وضع الستار (Position):', lang),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Slider(
                  value: widget.model.shutterPosition,
                  label: "${(widget.model.shutterPosition * 100).toInt()}%",
                  onChanged: (value) {
                    widget.model.setShutterPosition(value);
                  },
                ),
              ],

              const Divider(height: 20),

              if (!widget.model.isPVC &&
                  widget.model.systemMode != 'sliding' &&
                  (widget.model.hasBottomFrame ||
                      widget.model.hasFramePlintheBottom)) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate(
                      'استخدام بلانت بالأسفل (للإطار)',
                      lang,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.hasFramePlintheBottom,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) {
                    widget.model.toggleFramePlintheBottom(value);
                  },
                ),
              ],

              if (widget.model.hasBottomFrame &&
                  widget.model.systemMode != 'sliding') ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('سيستم او بي (System OB)', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.useSystemOB,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) {
                    widget.model.toggleSystemOB(value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('ديمي او بي (Demi OB)', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.useDemiOB,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) {
                    widget.model.toggleDemiOB(value);
                  },
                ),
                if (widget.model.zones.any(
                      (z) => z.content == ZoneContent.doubleSash,
                ))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Localization.translate(
                        'فيرو سونترال (Verrou Central)',
                        lang,
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: widget.model.useVerrouCentral,
                    activeColor: Colors.blue,
                    onChanged: (value) {
                      widget.model.toggleVerrouCentral(value);
                    },
                  ),
              ],

              const Divider(height: 30),

              // 🟢 2. قسم تدعيم المونطو (يظهر دائماً في الأسفل)
              // 🟢 هذا الجزء يحل مشكلة تدعيم المونطو (Renfort)
              Text(
                Localization.translate('تدعيم المونطو (Renfort)', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),

              Builder(
                builder: (context) {
                  // 1. تحديد السلاسل التي تدعم هذه الخاصية
                  final String seriesName =
                      activeSeriesForSystem?.name.toLowerCase() ?? '';
                  final bool isSupported =
                      seriesName.contains('67000') ||
                          seriesName.contains('h36') ||
                          seriesName.contains('h30') ||
                          seriesName.contains('hps');

                  // 2. إذا كانت السلسلة مدعومة ويوجد نظام منزلق
                  if (isSupported && firstSlidingZone != null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Localization.translate('الجانبي (Latéral):', lang),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            buildCompactOption(
                              Localization.translate('يسرى', lang),
                              'lateral_0',
                              firstSlidingZone,
                            ),
                            buildCompactOption(
                              Localization.translate('يمنى', lang),
                              'lateral_1',
                              firstSlidingZone,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          Localization.translate('المركزي (Central):', lang),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Wrap(
                          children: List.generate(centralCount, (index) {
                            return SizedBox(
                              width: 120,
                              child: buildCompactOption(
                                'مركز $index',
                                'central_$index',
                                firstSlidingZone,
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  }
                  // 3. إذا كانت السلسلة غير مدعومة
                  else if (firstSlidingZone != null) {
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        Localization.translate(
                          'هذه السلسلة لا تدعم تدعيم المونطو',
                          lang,
                        ),
                        style: const TextStyle(color: Colors.red, fontSize: 11),
                      ),
                    );
                  }
                  // 4. إذا لم يكن هناك نظام منزلق أصلاً
                  else {
                    return const SizedBox.shrink();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// Uses the exact same formula as [WindowPainter] for the number written
  /// inside a sash profile.  The dialog therefore never opens with a value
  /// that differs by the PVC welding loss or by the series overlap.
  double _openingSashOverlapForDrawing() => widget.model.openingSashOverlap;

  double _shownDoubleSashCuttingWidth(WindowZone zone, double ratio) {
    final weldLoss = widget.model.isPVC ? 5.0 : 0.0;
    final totalCutWidth =
        zone.boundary.width + _openingSashOverlapForDrawing() * 2;
    return totalCutWidth * ratio - weldLoss;
  }

  String _shownDimensionText(double value) {
    final rounded = (value * 10).round() / 10;
    return (rounded - rounded.round()).abs() < 0.001
        ? rounded.round().toString()
        : rounded.toStringAsFixed(1);
  }

  void _showInnerResizeDialog(BuildContext context, InnerDimensionHit hit) {
    // تم إزالة قفل الارتفاع لتتمكن من تعديل الطول والعرض براحتك
    final zone = widget.model.zones.firstWhere((z) => z.id == hit.zoneId);
    double currentValue = 0;
    String title = '';

    if (hit.isSashDivision) {
      final isRight = hit.isDoubleSashRight;
      final sashT =
          zone.sashThickness ??
              widget.model.getSectionThickness('sash', fallback: 45.0);
      final dividerT = widget.model.getSectionThickness(
        'mullion',
        fallback: sashT,
      );
      Rect parentR = zone.boundary;
      Rect sashR = parentR;
      if (zone.content == ZoneContent.doubleSash) {
        final sep = 4.0;
        final midX = parentR.left + parentR.width * zone.doubleSashRatio;
        if (!isRight) {
          sashR = Rect.fromLTRB(
            parentR.left,
            parentR.top,
            midX - sep / 2,
            parentR.bottom,
          );
        } else {
          sashR = Rect.fromLTRB(
            midX + sep / 2,
            parentR.top,
            parentR.right,
            parentR.bottom,
          );
        }
      }
      final glassR = widget.model.getSafeGlassRect(sashR, sashT);

      final hPositions = isRight
          ? zone.rightInnerHPositions
          : zone.innerHPositions;
      final vPositions = isRight
          ? zone.rightInnerVPositions
          : zone.innerVPositions;
      final innerH = isRight ? zone.rightInnerH : zone.innerH;
      final innerV = isRight ? zone.rightInnerV : zone.innerV;

      List<double> finalHPos = List.from(hPositions);
      if (finalHPos.isEmpty && innerH > 0) {
        double stepY = 1.0 / (innerH + 1);
        for (int i = 1; i <= innerH; i++) {
          finalHPos.add(stepY * i);
        }
      }
      List<double> finalVPos = List.from(vPositions);
      if (finalVPos.isEmpty && innerV > 0) {
        double stepX = 1.0 / (innerV + 1);
        for (int i = 1; i <= innerV; i++) {
          finalVPos.add(stepX * i);
        }
      }

      if (hit.isWidth) {
        int cols = finalVPos.length + 1;
        int col = hit.divisionIndex;
        double leftRatio = col == 0 ? 0.0 : finalVPos[col - 1];
        double rightRatio = col == cols - 1 ? 1.0 : finalVPos[col];
        double left = glassR.left + (glassR.width * leftRatio);
        if (col > 0) left += dividerT / 2;
        double right = glassR.left + (glassR.width * rightRatio);
        if (col < cols - 1) right -= dividerT / 2;
        currentValue = right - left;
        title = 'تعديل عرض الخلية الداخلية';
      } else {
        int rows = finalHPos.length + 1;
        int row = hit.divisionIndex;
        double topRatio = row == 0 ? 0.0 : finalHPos[row - 1];
        double bottomRatio = row == rows - 1 ? 1.0 : finalHPos[row];
        double top = glassR.top + (glassR.height * topRatio);
        if (row > 0) top += dividerT / 2;
        double bottom = glassR.top + (glassR.height * bottomRatio);
        if (row < rows - 1) bottom -= dividerT / 2;
        currentValue = bottom - top;
        title = 'تعديل ارتفاع الخلية الداخلية';
      }
    } else if (hit.isDoubleSashLeft) {
      final effectiveRatio = widget.model.isInternalView
          ? zone.doubleSashRatio
          : 1.0 - zone.doubleSashRatio;
      currentValue = _shownDoubleSashCuttingWidth(zone, effectiveRatio);
      title = 'تعديل عرض الدلفة اليسرى';
    } else if (hit.isDoubleSashRight) {
      final effectiveRatio = widget.model.isInternalView
          ? zone.doubleSashRatio
          : 1.0 - zone.doubleSashRatio;
      currentValue = _shownDoubleSashCuttingWidth(
        zone,
        1.0 - effectiveRatio,
      );
      title = 'تعديل عرض الدلفة اليمنى';
    } else {
      currentValue = hit.isWidth ? zone.boundary.width : zone.boundary.height;
      title = hit.isWidth ? 'تعديل عرض التقسيم' : 'تعديل ارتفاع التقسيم';
    }

    final ctrl = TextEditingController(text: _shownDimensionText(currentValue));

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme
            .of(context)
            .brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: 'القياس الداخلي (mm)',
              labelStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: isDark ? Colors.white70 : Colors.blueGrey,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (val != null) {
                  if (hit.isSashDivision) {
                    if (val >= 50) {
                      // الحد الأدنى 50 ملم
                      final isRight = hit.isDoubleSashRight;
                      final sashT =
                          zone.sashThickness ??
                              widget.model.getSectionThickness(
                                'sash',
                                fallback: 45.0,
                              );
                      final dividerT = widget.model.getSectionThickness(
                        'mullion',
                        fallback: sashT,
                      );
                      Rect parentR = zone.boundary;
                      Rect sashR = parentR;
                      if (zone.content == ZoneContent.doubleSash) {
                        final sep = 4.0;
                        final midX =
                            parentR.left + parentR.width * zone.doubleSashRatio;
                        if (!isRight) {
                          sashR = Rect.fromLTRB(
                            parentR.left,
                            parentR.top,
                            midX - sep / 2,
                            parentR.bottom,
                          );
                        } else {
                          sashR = Rect.fromLTRB(
                            midX + sep / 2,
                            parentR.top,
                            parentR.right,
                            parentR.bottom,
                          );
                        }
                      }
                      final glassR = widget.model.getSafeGlassRect(
                        sashR,
                        sashT,
                      );

                      final hPositions = isRight
                          ? zone.rightInnerHPositions
                          : zone.innerHPositions;
                      final vPositions = isRight
                          ? zone.rightInnerVPositions
                          : zone.innerVPositions;
                      final innerH = isRight ? zone.rightInnerH : zone.innerH;
                      final innerV = isRight ? zone.rightInnerV : zone.innerV;

                      List<double> finalHPos = List.from(hPositions);
                      if (finalHPos.isEmpty && innerH > 0) {
                        for (int i = 1; i <= innerH; i++) {
                          finalHPos.add((1.0 / (innerH + 1)) * i);
                        }
                      }
                      List<double> finalVPos = List.from(vPositions);
                      if (finalVPos.isEmpty && innerV > 0) {
                        for (int i = 1; i <= innerV; i++) {
                          finalVPos.add((1.0 / (innerV + 1)) * i);
                        }
                      }

                      if (hit.isWidth) {
                        int cols = finalVPos.length + 1;
                        int col = hit.divisionIndex;
                        if (col < cols - 1) {
                          double leftRatio = col == 0
                              ? 0.0
                              : finalVPos[col - 1];
                          double left =
                              glassR.left + (glassR.width * leftRatio);
                          double leftAdjusted =
                              left + (col > 0 ? dividerT / 2 : 0);
                          double rightAdjusted = leftAdjusted + val;
                          double right =
                              rightAdjusted +
                                  (col < cols - 1 ? dividerT / 2 : 0);
                          double newRightRatio =
                          ((right - glassR.left) / glassR.width).clamp(
                            0.05,
                            0.95,
                          );
                          widget.model.updateZoneInnerVDivisionRatio(
                            hit.zoneId,
                            isRight,
                            col,
                            newRightRatio,
                          );
                        } else if (col > 0) {
                          double rightRatio = 1.0;
                          double right =
                              glassR.left + (glassR.width * rightRatio);
                          double rightAdjusted =
                              right - (col < cols - 1 ? dividerT / 2 : 0);
                          double leftAdjusted = rightAdjusted - val;
                          double leftNew =
                              leftAdjusted - (col > 0 ? dividerT / 2 : 0);
                          double newLeftRatio =
                          ((leftNew - glassR.left) / glassR.width).clamp(
                            0.05,
                            0.95,
                          );
                          widget.model.updateZoneInnerVDivisionRatio(
                            hit.zoneId,
                            isRight,
                            col - 1,
                            newLeftRatio,
                          );
                        }
                      } else {
                        int rows = finalHPos.length + 1;
                        int row = hit.divisionIndex;
                        if (row < rows - 1) {
                          double topRatio = row == 0 ? 0.0 : finalHPos[row - 1];
                          double top = glassR.top + (glassR.height * topRatio);
                          double topAdjusted =
                              top + (row > 0 ? dividerT / 2 : 0);
                          double bottomAdjusted = topAdjusted + val;
                          double bottom =
                              bottomAdjusted +
                                  (row < rows - 1 ? dividerT / 2 : 0);
                          double newBottomRatio =
                          ((bottom - glassR.top) / glassR.height).clamp(
                            0.05,
                            0.95,
                          );
                          widget.model.updateZoneInnerHDivisionRatio(
                            hit.zoneId,
                            isRight,
                            row,
                            newBottomRatio,
                          );
                        } else if (row > 0) {
                          double bottomRatio = 1.0;
                          double bottom =
                              glassR.top + (glassR.height * bottomRatio);
                          double bottomAdjusted =
                              bottom - (row < rows - 1 ? dividerT / 2 : 0);
                          double topAdjusted = bottomAdjusted - val;
                          double topNew =
                              topAdjusted - (row > 0 ? dividerT / 2 : 0);
                          double newTopRatio =
                          ((topNew - glassR.top) / glassR.height).clamp(
                            0.05,
                            0.95,
                          );
                          widget.model.updateZoneInnerHDivisionRatio(
                            hit.zoneId,
                            isRight,
                            row - 1,
                            newTopRatio,
                          );
                        }
                      }
                    }
                  } else if (hit.isDoubleSashLeft || hit.isDoubleSashRight) {
                    final rawVisualSashSize =
                        val + (widget.model.isPVC ? 5.0 : 0.0);
                    final totalCutWidth = zone.boundary.width +
                        _openingSashOverlapForDrawing() * 2;
                    final visualLeftRatio = (hit.isDoubleSashLeft
                        ? rawVisualSashSize / totalCutWidth
                        : 1.0 - (rawVisualSashSize / totalCutWidth))
                        .clamp(0.15, 0.85);
                    final ratio = widget.model.isInternalView
                        ? visualLeftRatio
                        : 1.0 - visualLeftRatio;
                    widget.model.updateZoneDoubleSashRatio(hit.zoneId, ratio);
                  } else {
                    if (val >= 50) {
                      widget.model.resizeZoneInner(
                        hit.zoneId,
                        hit.isWidth,
                        val,
                      );
                    }
                  }
                }
                Navigator.pop(context);
              },
              child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// Shows outer-dimension dialog for a single frame in a coupled window.
  void _showFrameResizeDialog(BuildContext context, InnerDimensionHit hit) {
    final zone = widget.model.zones.firstWhere((z) => z.id == hit.zoneId);
    final double pt = widget.model.profileThickness;
    double outerVal;
    String title;
    if (hit.isWidth) {
      outerVal = zone.boundary.width + 2 * pt;
      title = 'تعديل عرض الإطار (خارجي)';
    } else {
      outerVal = zone.boundary.height + 2 * pt;
      title = 'تعديل ارتفاع الإطار (خارجي)';
    }
    final ctrl = TextEditingController(text: outerVal.toInt().toString());
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme
            .of(ctx)
            .brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: hit.isWidth
                  ? 'العرض الخارجي (mm)'
                  : 'الارتفاع الخارجي (mm)',
              labelStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: isDark ? Colors.white70 : Colors.blueGrey,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final val = double.tryParse(ctrl.text);
                if (val != null && val >= 200) {
                  final delta = val - outerVal;
                  widget.model.resizeFrameFromHandles(
                    hit.zoneId,
                    moveLeft: false,
                    moveRight: hit.isWidth,
                    moveTop: false,
                    moveBottom: !hit.isWidth,
                    deltaX: hit.isWidth ? delta : 0.0,
                    deltaY: hit.isWidth ? 0.0 : delta,
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showResizeDialog(BuildContext context, {required bool focusWidth}) {
    final widthCtrl = TextEditingController(
      text: widget.model.width.toInt().toString(),
    );
    final heightCtrl = TextEditingController(
      text: widget.model.height.toInt().toString(),
    );
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme
            .of(context)
            .brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            'تعديل قياسات النافذة',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: widthCtrl,
                  autofocus: focusWidth,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'العرض الإجمالي (mm)',
                    labelStyle: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark ? Colors.white70 : Colors.blueGrey,
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: heightCtrl,
                  autofocus: !focusWidth,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'الارتفاع الإجمالي (mm)',
                    labelStyle: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark ? Colors.white70 : Colors.blueGrey,
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final w = double.tryParse(widthCtrl.text) ?? widget.model.width;
                final h =
                    double.tryParse(heightCtrl.text) ?? widget.model.height;
                if (w >= widget.model.profileThickness * 3 &&
                    h >= widget.model.profileThickness * 3) {
                  widget.model.resizeWindow(w, h);
                }
                Navigator.pop(context);
              },
              child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMullionTypeDialog(BuildContext context) async {
    final selection = widget.model.selection;
    if (selection.type != SelectionType.mullion ||
        selection.isHorizontalMullion == null ||
        selection.mullionPosition == null) {
      return;
    }

    final key =
        '${selection.isHorizontalMullion! ? 'H' : 'V'}_${selection.mullionPosition!.toStringAsFixed(1)}';
    final currentType =
        widget.model.mullionProfiles[key] ?? MullionProfileType.standard;

    SimpleDialogOption typeOption(
      MullionProfileType type,
      String label,
      IconData icon,
    ) {
      return SimpleDialogOption(
        onPressed: () {
          widget.model.setMullionProfile(type);
          Navigator.pop(context);
        },
        child: Row(
          children: [
            Icon(
              icon,
              color: type == currentType
                  ? Colors.green.shade700
                  : Colors.blueGrey,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            if (type == currentType)
              Icon(Icons.check_circle, color: Colors.green.shade700),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('نوع التقسيم'),
        children: [
          typeOption(
            MullionProfileType.standard,
            'Traverse — تقسيم عادي',
            Icons.horizontal_rule_rounded,
          ),
          typeOption(
            MullionProfileType.flat,
            'Cadre double — إطار مزدوج',
            Icons.splitscreen_rounded,
          ),
          typeOption(
            MullionProfileType.grooved,
            'Cadre 140 — إطار بتجويف واحد',
            Icons.view_headline_rounded,
          ),
          if (currentType == MullionProfileType.grooved)
            SimpleDialogOption(
              onPressed: () {
                widget.model.toggleGroovedMullionCavity(
                  selection.isHorizontalMullion!,
                  selection.mullionPosition!,
                );
                Navigator.pop(dialogContext);
              },
              child: const Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, color: Colors.blue),
                  SizedBox(width: 12),
                  Text('عكس اتجاه التجويف'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMullionToolbar(BuildContext context) {
    String key =
        "${widget.model.selection.isHorizontalMullion! ? 'H' : 'V'}_${widget
        .model.selection.mullionPosition!.toStringAsFixed(1)}";
    MullionProfileType currentType =
        widget.model.mullionProfiles[key] ?? MullionProfileType.standard;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.blue.shade900.withValues(alpha: 0.8),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded, color: Colors.white),
          const SizedBox(width: 10),
          const Text(
            'العمود محدد',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          DropdownButton<MullionProfileType>(
            dropdownColor: Colors.blue.shade800,
            value: currentType,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            underline: Container(height: 1, color: Colors.white38),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            items: const [
              DropdownMenuItem(
                value: MullionProfileType.standard,
                child: Text('Traverse'),
              ),
              DropdownMenuItem(
                value: MullionProfileType.flat,
                child: Text('Cadre doublé'),
              ),
              DropdownMenuItem(
                value: MullionProfileType.grooved,
                child: Text('Cadre 140'),
              ),
            ],
            onChanged: (val) {
              if (val != null) widget.model.setMullionProfile(val);
            },
          ),
          const SizedBox(width: 15),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 18),
            label: const Text('حذف', style: TextStyle(color: Colors.white)),
            onPressed: () => widget.model.deleteSelectedMullion(),
          ),
        ],
      ),
    );
  }

  Widget _buildInnerDivisionToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.blue.shade900.withValues(alpha: 0.8),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded, color: Colors.white),
          const SizedBox(width: 10),
          const Text(
            'التقسيم محدد (اسحب للتحريك)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 18),
            label: const Text('حذف', style: TextStyle(color: Colors.white)),
            onPressed: () => widget.model.deleteSelectedInnerDivision(),
          ),
        ],
      ),
    );
  }

  Widget buildSideCoverSegmentsControl(
    BuildContext context,
    WindowModel model,
    AppLanguage lang,
  ) {
    if (!model.hasSideCovers) return const SizedBox.shrink();

    String labelFor(String side) {
      switch (side) {
        case 'top':
          return Localization.translate('علوية', lang);
        case 'left':
          return Localization.translate('يسرى', lang);
        case 'right':
          return Localization.translate('يمنى', lang);
        case 'bottom':
          return Localization.translate('سفلية', lang);
        default:
          return side;
      }
    }

    Widget sideButton(String side) {
      final enabled = model.isSideCoverSegmentEnabled(side);
      final disabledBottom = side == 'bottom' && !model.hasBottomFrame;
      return Tooltip(
        message: Localization.translate(
          'ضغطة للتفعيل أو التعطيل، واضغط مطولا لتخصيص الغطاء',
          lang,
        ),
        child: GestureDetector(
          onLongPress: disabledBottom
              ? null
              : () => _showSideCoverSegmentDialog(context, side),
          onSecondaryTap: disabledBottom
              ? null
              : () => _showSideCoverSegmentDialog(context, side),
          child: FilterChip(
            labelStyle: const TextStyle(fontSize: 10),
            label: Text(labelFor(side)),
            selected: enabled && !disabledBottom,
            onSelected: disabledBottom
                ? null
                : (_) => model.toggleSideCoverSegment(side),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Localization.translate(
            'ضغطة للتفعيل أو التعطيل، واضغط مطولا على الجهة لتخصيصها',
            lang,
          ),
          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            sideButton('top'),
            sideButton('left'),
            sideButton('right'),
            sideButton('bottom'),
          ],
        ),
      ],
    );
  }

  Future<void> _showSideCoverSegmentDialog(
    BuildContext context,
    String side,
  ) async {
    final model = widget.model;
    final sideLength = model.sideCoverSideLength(side);
    if (sideLength <= 0) return;

    final existing = model.sideCoverSegmentForSide(side);
    final vertical = side == 'left' || side == 'right';
    final leading = vertical ? 'الأعلى' : 'اليسار';
    final trailing = vertical ? 'الأسفل' : 'اليمين';
    final startController = TextEditingController(
      text: (existing?.startOffset ?? 0).toStringAsFixed(0),
    );
    final secondController = TextEditingController(
      text: (existing?.length ?? sideLength).toStringAsFixed(0),
    );
    final visibleController = TextEditingController(
      text: (existing?.visibleWidth ?? model.sideCoverWidth).toStringAsFixed(0),
    );
    bool fromTrailing = false;
    bool useEndOffset = false;

    double readValue(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? -1;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final startLabel = fromTrailing ? trailing : leading;
          final endLabel = fromTrailing ? leading : trailing;
          return AlertDialog(
            title: Text('تخصيص غطاء الجهة ${vertical ? (side == 'right' ? 'اليمنى' : 'اليسرى') : (side == 'top' ? 'العلوية' : 'السفلية')}'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 330,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text('من $leading'),
                          selected: !fromTrailing,
                          onSelected: (_) => setDialogState(() {
                            fromTrailing = false;
                          }),
                        ),
                        ChoiceChip(
                          label: Text('من $trailing'),
                          selected: fromTrailing,
                          onSelected: (_) => setDialogState(() {
                            fromTrailing = true;
                          }),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('إدخال النهاية بدل الطول'),
                      value: useEndOffset,
                      onChanged: (value) => setDialogState(() {
                        useEndOffset = value;
                      }),
                    ),
                    TextField(
                      controller: startController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'بداية الغطاء من $startLabel (مم)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: secondController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: useEndOffset
                            ? 'نهاية الغطاء قبل $endLabel (مم)'
                            : 'طول الغطاء على الإطار (مم)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: visibleController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'العرض الظاهر خارج الإطار (مم)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'طول الجهة: ${sideLength.toStringAsFixed(0)} مم',
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (existing != null)
                TextButton.icon(
                  onPressed: () {
                    model.removeSideCoverSegment(side);
                    Navigator.pop(dialogContext);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('حذف', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  final first = readValue(startController);
                  final second = readValue(secondController);
                  final visible = readValue(visibleController);
                  if (first < 0 || second < 0 || visible < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('أدخل قياسات صحيحة')),
                    );
                    return;
                  }

                  double start;
                  double end;
                  if (!fromTrailing) {
                    start = first;
                    end = useEndOffset ? sideLength - second : start + second;
                  } else {
                    end = sideLength - first;
                    start = useEndOffset ? second : end - second;
                  }
                  start = start.clamp(0.0, sideLength).toDouble();
                  end = end.clamp(0.0, sideLength).toDouble();
                  if (end <= start) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('يجب أن تكون نهاية الغطاء بعد بدايته'),
                      ),
                    );
                    return;
                  }

                  model.saveSideCoverSegment(
                    SideCoverSegment(
                      side: side,
                      startOffset: start,
                      endOffset: end,
                      visibleWidth: visible,
                    ),
                  );
                  Navigator.pop(dialogContext);
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
    startController.dispose();
    secondController.dispose();
    visibleController.dispose();
  }

  Widget buildShutterSidesControl(BuildContext context,
      WindowModel model,
      AppLanguage lang,) {
    if (!model.hasSideCovers && !model.hasShutter) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6.0,
          runSpacing: 4.0,
          children: [
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(Localization.translate('علوية', lang)),
              selected: !model.removedShutterSides.contains('top'),
              onSelected: (_) => model.toggleShutterSide('top'),
            ),
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(Localization.translate('يسرى', lang)),
              selected: !model.removedShutterSides.contains('left'),
              onSelected: (_) => model.toggleShutterSide('left'),
            ),
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(Localization.translate('يمنى', lang)),
              selected: !model.removedShutterSides.contains('right'),
              onSelected: (_) => model.toggleShutterSide('right'),
            ),
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(Localization.translate('سفلية', lang)),
              selected:
              model.hasBottomFrame &&
                  !model.removedShutterSides.contains('bottom'),
              onSelected: model.hasBottomFrame
                  ? (_) => model.toggleShutterSide('bottom')
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    final primarySeries = widget.systemMode == 'sliding'
        ? widget.model.activeSlidingSeries
        : widget.model.activeSeries;

    final primaryItemsList = () {
      final List<AluminumSeries> list = [];
      for (var system in widget.model.availableSystems) {
        final filtered = widget.systemMode == 'mixed'
            ? system.series.where((series) {
          final name = series.name.toLowerCase();
          final type = series.type.toLowerCase();
          return name.contains('frappe') ||
              name.contains('battant') ||
              name.contains('فتح') ||
              name.contains('فرنسي') ||
              name.contains('ouvrant') ||
              type.contains('frappe') ||
              type.contains('battant') ||
              type.contains('فتح') ||
              type.contains('فرنسي') ||
              type.contains('ouvrant');
        })
            : system.series;
        final selectorMode = widget.systemMode == 'sliding'
            ? 'sliding'
            : 'french';
        list.addAll(
          filtered.where(
                (series) =>
                seriesMatchesDrawingMode(series, system, selectorMode),
          ),
        );
        for (final series in system.series) {
          if (seriesMatchesDrawingMode(series, system, selectorMode) &&
              !list.any((item) => item.id == series.id)) {
            list.add(series);
          }
        }
      }
      if (primarySeries != null && !list.any((s) => s.id == primarySeries.id)) {
        list.add(primarySeries);
      }

      final uniqueList = <AluminumSeries>[];
      for (final s in list) {
        if (!uniqueList.any((existing) => existing.id == s.id)) {
          uniqueList.add(s);
        }
      }
      return uniqueList;
    }();

    final safePrimaryValue =
    (primarySeries != null &&
        primaryItemsList.any((s) => s.id == primarySeries.id))
        ? primaryItemsList.firstWhere((s) => s.id == primarySeries.id)
        : null;

    final slidingItemsList = () {
      final activeSystemId = widget.model.activeSeries?.profileId;
      if (activeSystemId == null || widget.model.availableSystems.isEmpty) {
        return <AluminumSeries>[];
      }
      final systemMatches = widget.model.availableSystems.where(
            (sys) => sys.id == activeSystemId,
      );
      if (systemMatches.isEmpty) return <AluminumSeries>[];
      final system = systemMatches.first;
      final List<AluminumSeries> list = system.series.where((series) {
        final name = series.name.toLowerCase();
        final type = series.type.toLowerCase();
        return name.contains('couliss') ||
            name.contains('sliding') ||
            name.contains('منزلق') ||
            type.contains('couliss') ||
            type.contains('sliding') ||
            type.contains('منزلق');
      }).toList();

      for (final series in system.series) {
        if (isSlidingSeriesForDrawing(series) &&
            !list.any((item) => item.id == series.id)) {
          list.add(series);
        }
      }
      if (widget.model.activeSlidingSeries != null &&
          !list.any((s) => s.id == widget.model.activeSlidingSeries!.id)) {
        list.add(widget.model.activeSlidingSeries!);
      }

      final uniqueList = <AluminumSeries>[];
      for (final s in list) {
        if (!uniqueList.any((existing) => existing.id == s.id)) {
          uniqueList.add(s);
        }
      }
      return uniqueList;
    }();

    final safeSlidingValue =
    (widget.model.activeSlidingSeries != null &&
        slidingItemsList.any(
              (s) => s.id == widget.model.activeSlidingSeries!.id,
        ))
        ? slidingItemsList.firstWhere(
          (s) => s.id == widget.model.activeSlidingSeries!.id,
    )
        : null;

    return AppBar(
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      foregroundColor: isDark ? Colors.white : Colors.black,
      elevation: 0.5,
      titleSpacing: 8,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (widget.model.availableSystems.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 160),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withValues(alpha: 0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.blue.shade800 : Colors.blue.shade200,
                  ),
                ),
                child: DropdownButton<AluminumSeries>(
                  isExpanded: true,
                  value: safePrimaryValue,
                  dropdownColor: isDark
                      ? const Color(0xFF1E1E2C)
                      : Colors.white,
                  hint: Text(
                    widget.systemMode == 'mixed'
                        ? 'سلسلة الفتح'
                        : 'اختر السلسلة',
                    style: TextStyle(
                      color: isDark ? Colors.blue.shade300 : Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                  underline: const SizedBox(),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: isDark ? Colors.blue.shade300 : Colors.blue,
                    size: 18,
                  ),
                  items: primaryItemsList.map((series) {
                    final systemMatches = widget.model.availableSystems.where(
                          (sys) => sys.series.any((s) => s.id == series.id),
                    );
                    final systemName = systemMatches.isNotEmpty
                        ? systemMatches.first.name
                        : '';
                    return DropdownMenuItem<AluminumSeries>(
                      value: series,
                      child: Text(
                        systemName.isNotEmpty
                            ? '$systemName - ${series.name}'
                            : series.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.blue.shade300 : Colors.blue,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.visible,
                      ),
                    );
                  }).toList(),
                  onChanged: (AluminumSeries? newSeries) {
                    if (newSeries != null) {
                      widget.model.setActiveSeries(newSeries);
                    }
                  },
                ),
              ),
              if (widget.systemMode == 'mixed' && isSlidingSupported) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.green.shade900.withValues(alpha: 0.3)
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.green.shade800
                          : Colors.green.shade200,
                    ),
                  ),
                  child: DropdownButton<AluminumSeries>(
                    isExpanded: true,
                    value: safeSlidingValue,
                    dropdownColor: isDark
                        ? const Color(0xFF1E1E2C)
                        : Colors.white,
                    hint: Text(
                      'سلسلة المنزلق',
                      style: TextStyle(
                        color: isDark ? Colors.green.shade300 : Colors.green,
                        fontSize: 12,
                      ),
                    ),
                    underline: const SizedBox(),
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: isDark ? Colors.green.shade300 : Colors.green,
                      size: 18,
                    ),
                    items: slidingItemsList.map((series) {
                      final systemMatches = widget.model.availableSystems.where(
                            (s) => s.series.any((ser) => ser.id == series.id),
                      );
                      final systemName = systemMatches.isNotEmpty
                          ? systemMatches.first.name
                          : '';
                      return DropdownMenuItem<AluminumSeries>(
                        value: series,
                        child: Text(
                          systemName.isNotEmpty
                              ? '$systemName - ${series.name}'
                              : series.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.green.shade300
                                : Colors.green,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.visible,
                        ),
                      );
                    }).toList(),
                    onChanged: (AluminumSeries? newSeries) {
                      if (newSeries != null) {
                        widget.model.setActiveSlidingSeries(newSeries);
                      }
                    },
                  ),
                ),
              ],
            ],

            const SizedBox(width: 8),

            // 🟢 زر التراجع
            if (_isWindowsDesktop)
              ..._buildWindowsAppBarDrawingControls(context),

            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              onPressed: widget.model.canUndo ? widget.model.undo : null,
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'تراجع',
              color: widget.model.canUndo ? Colors.black87 : Colors.black26,
            ),

            // 🟢 زر الإعادة (Redo)
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              onPressed: widget.model.canRedo ? widget.model.redo : null,
              icon: const Icon(Icons.redo_rounded),
              tooltip: 'إعادة',
              color: widget.model.canRedo ? Colors.black87 : Colors.black26,
            ),

            // When enabled, every new outer frame copies its neighbour's
            // corresponding width or height.
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              icon: Icon(
                Icons.copy_all_rounded,
                color: widget.model.copyPreviousFrameSize
                    ? Colors.blue.shade700
                    : Colors.black54,
              ),
              tooltip: widget.model.copyPreviousFrameSize
                  ? 'نسخ قياس الإطار السابق: مفعّل'
                  : 'نسخ قياس الإطار السابق',
              onPressed: widget.model.toggleCopyPreviousFrameSize,
            ),

            // 🟢 زر مسح الرسم بالكامل
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
              tooltip: 'مسح الرسم',
              onPressed: () => _showClearAllDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitToolbar(BuildContext context, bool hasSelection) {
    final lang = Provider
        .of<AppSettingsProvider>(context)
        .language;
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () {
                _showResizeDialog(context, focusWidth: true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withValues(alpha: 0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? Colors.blue.shade800 : Colors.blue.shade200,
                  ),
                ),
                child: Text(
                  'Dim: ${widget.model.width.toInt()} * ${widget.model.height
                      .toInt()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // زر التبديل بين الأوضاع
            InkWell(
              onTap: () {
                if (widget.model.isDrawingMode) {
                  _stopDrawingTimer();
                } else {
                  _startDrawingTimer();
                }
                setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.model.isDrawingMode
                      ? Colors.green.shade600
                      : Colors.blueGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.model.isDrawingMode
                      ? Localization.translate('وضع الرسم', lang)
                      : Localization.translate('وضع التحريك', lang),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // زر إعادة التكبير
            InkWell(
              onTap: () {
                setState(() {
                  _userScale = 1.0;
                  _userPan = Offset.zero;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withValues(alpha: 0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? Colors.blue.shade800 : Colors.blue.shade200,
                  ),
                ),
                child: Icon(
                  Icons.zoom_out_map_rounded,
                  color: isDark ? Colors.blue.shade300 : Colors.blue,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            backgroundColor: Colors.white,
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'مسح الرسم',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
            content: const Text(
              'هل أنت متأكد أنك تريد مسح الرسم بالكامل والبدء من جديد؟',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  widget.model.clearAll();
                  Navigator.pop(context);
                },
                child: const Text(
                  'نعم، امسح',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showSplitDialog(BuildContext context, bool isHorizontal) {
    final zone = widget.model.selectedZone;
    if (zone == null) return;
    final double totalNetSize = isHorizontal
        ? zone.boundary.height - widget.model.profileThickness
        : zone.boundary.width - widget.model.profileThickness;
    int parts = 2;
    bool isEqualSplit = true;
    bool fromStart = true;
    TextEditingController part1Ctrl = TextEditingController();
    TextEditingController part2Ctrl = TextEditingController();

    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark ? Colors.white70 : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final dropdownBgColor = isDark ? const Color(0xFF2D2D3F) : Colors.white;

    String getRemainingText() {
      if (parts == 2) {
        double p1 = double.tryParse(part1Ctrl.text) ?? 0;
        return '${Localization.translate('المتبقي', lang)}: ${(totalNetSize -
            p1).toStringAsFixed(1)} mm';
      } else if (parts == 3) {
        double p1 = double.tryParse(part1Ctrl.text) ?? 0;
        double p2 = double.tryParse(part2Ctrl.text) ?? 0;
        return '${Localization.translate(
            'القطعة الوسطى', lang)}: ${(totalNetSize - p1 - p2).toStringAsFixed(
            1)} mm';
      }
      return '';
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: Text(
                Localization.translate(
                  isHorizontal
                      ? 'تفاصيل التقسيم الأفقي'
                      : 'تفاصيل التقسيم العمودي',
                  lang,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: textColor,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<bool>(
                      title: Text(
                        Localization.translate('تقسيم متساوي', lang),
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      value: true,
                      groupValue: isEqualSplit,
                      onChanged: (v) => setState(() => isEqualSplit = v!),
                      activeColor: Colors.blue,
                    ),
                    RadioListTile<bool>(
                      title: Text(
                        Localization.translate('قياس مخصص', lang),
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      value: false,
                      groupValue: isEqualSplit,
                      onChanged: (v) =>
                          setState(() {
                            isEqualSplit = v!;
                            part1Ctrl.clear();
                            part2Ctrl.clear();
                          }),
                      activeColor: Colors.blue,
                    ),
                    Divider(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                    ),
                    if (isEqualSplit)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              Localization.translate(
                                'إلى كم قطعة تقسمها؟',
                                lang,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: parts,
                            dropdownColor: dropdownBgColor,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            items: List.generate(9, (index) => index + 2)
                                .map(
                                  (e) =>
                                  DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      '$e ${Localization.translate(
                                          'قطع', lang)}',
                                    ),
                                  ),
                            )
                                .toList(),
                            onChanged: (v) => setState(() => parts = v!),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  Localization.translate('عدد القطع:', lang),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: parts,
                                dropdownColor: dropdownBgColor,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                items: [2, 3]
                                    .map(
                                      (e) =>
                                      DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          '$e ${Localization.translate(
                                              'قطع', lang)}',
                                        ),
                                      ),
                                )
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() {
                                      parts = v!;
                                      part1Ctrl.clear();
                                      part2Ctrl.clear();
                                    }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${Localization.translate(
                                'إجمالي القياس الصافي', lang)}: ${totalNetSize
                                .toStringAsFixed(1)} mm',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 15),
                          if (parts == 2) ...[
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    Localization.translate(
                                      'من أين يبدأ القياس؟',
                                      lang,
                                    ),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                DropdownButton<bool>(
                                  value: fromStart,
                                  dropdownColor: dropdownBgColor,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: true,
                                      child: Text(
                                        isHorizontal
                                            ? Localization.translate(
                                          'من الأعلى',
                                          lang,
                                        )
                                            : Localization.translate(
                                          'من اليسار',
                                          lang,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: false,
                                      child: Text(
                                        isHorizontal
                                            ? Localization.translate(
                                          'من الأسفل',
                                          lang,
                                        )
                                            : Localization.translate(
                                          'من اليمين',
                                          lang,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => fromStart = v!),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: part1Ctrl,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                labelText: Localization.translate(
                                  'أدخل البُعد (mm)',
                                  lang,
                                ),
                                labelStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey,
                                  ),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              getRemainingText(),
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ] else
                            if (parts == 3) ...[
                              TextField(
                                controller: part1Ctrl,
                                onChanged: (_) => setState(() {}),
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                                decoration: InputDecoration(
                                  labelText: Localization.translate(
                                    isHorizontal
                                        ? 'القطعة العلوية (mm)'
                                        : 'القطعة اليسرى (mm)',
                                    lang,
                                  ),
                                  labelStyle: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.grey,
                                    ),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.blue),
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: part2Ctrl,
                                onChanged: (_) => setState(() {}),
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                                decoration: InputDecoration(
                                  labelText: Localization.translate(
                                    isHorizontal
                                        ? 'القطعة السفلية (mm)'
                                        : 'القطعة اليمنى (mm)',
                                    lang,
                                  ),
                                  labelStyle: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.grey,
                                    ),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.blue),
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                getRemainingText(),
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                        ],
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (zone.content != ZoneContent.empty &&
                        zone.content != ZoneContent.fixedGlass) {
                      widget.model.removeSashDivisions();
                    }
                    Navigator.pop(context);
                  },
                  child: Text(
                    (zone.content != ZoneContent.empty &&
                        zone.content != ZoneContent.fixedGlass)
                        ? Localization.translate('حذف التقسيم', lang)
                        : Localization.translate('إلغاء', lang),
                    style: TextStyle(
                      color:
                      (zone.content != ZoneContent.empty &&
                          zone.content != ZoneContent.fixedGlass)
                          ? Colors.red
                          : (isDark ? Colors.white60 : Colors.grey),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () {
                    if (isEqualSplit) {
                      if (isHorizontal) {
                        widget.model.splitSelectedZoneHorizontal(parts: parts);
                      } else {
                        widget.model.splitSelectedZoneVertical(parts: parts);
                      }
                    } else {
                      List<double> customSizes = [];
                      if (parts == 2) {
                        double val =
                            double.tryParse(part1Ctrl.text) ??
                                (totalNetSize / 2);
                        customSizes.add(val);
                        if (isHorizontal) {
                          widget.model.splitSelectedZoneHorizontal(
                            parts: 2,
                            customSizes: customSizes,
                            fromTop: fromStart,
                          );
                        } else {
                          widget.model.splitSelectedZoneVertical(
                            parts: 2,
                            customSizes: customSizes,
                            fromLeft: fromStart,
                          );
                        }
                      } else if (parts == 3) {
                        double val1 =
                            double.tryParse(part1Ctrl.text) ??
                                (totalNetSize / 3);
                        double val2 =
                            double.tryParse(part2Ctrl.text) ??
                                (totalNetSize / 3);
                        customSizes.addAll([val1, val2]);
                        if (isHorizontal) {
                          widget.model.splitSelectedZoneHorizontal(
                            parts: 3,
                            customSizes: customSizes,
                          );
                        } else {
                          widget.model.splitSelectedZoneVertical(
                            parts: 3,
                            customSizes: customSizes,
                          );
                        }
                      }
                    }
                    Navigator.pop(context);
                  },
                  child: Text(
                    Localization.translate('تطبيق', lang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildContentToolbar(BuildContext context) {
    final zone = widget.model.selectedZone!;
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    String seriesName = activeSeriesForSystem != null
        ? activeSeriesForSystem!.name.toLowerCase()
        : '';
    String slidingSeriesName = widget.model.activeSlidingSeries != null
        ? widget.model.activeSlidingSeries!.name.toLowerCase()
        : seriesName;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: BoxConstraints(
        maxHeight: MediaQuery
            .of(context)
            .size
            .height * 0.40,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: SingleChildScrollView(
        controller: _glassScrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🟢 زر إعدادات الإطار المربوط بقاعدة البيانات
            Text(
              Localization.translate('إعدادات الإطار والظلفة:', lang),
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ContentButton(
                    label: widget.model.frameOverride != null
                        ? '${widget.model.frameOverride!['name']}'
                        : Localization.translate('اختر الإطار (Cadre)', lang),
                    icon: Icons.border_outer_rounded,
                    selected: widget.model.frameOverride != null,
                    onPressed: () async {
                      final selected = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) =>
                            ProfileSelectorDialog(
                              profileType: 'Frame',
                              seriesId: activeSeriesForSystem?.id,
                            ),
                      );
                      if (selected != null) {
                        double price = 0.0;
                        if (widget.model.selectedDbColor != null) {
                          int colorId = widget.model.selectedDbColor!['id'];
                          final db = SqlDatabase();
                          price = await db.getSectionPrice(
                            selected['id'],
                            colorId,
                          );
                        }
                        final mutableSelected = Map<String, dynamic>.from(
                          selected,
                        );
                        mutableSelected['calculated_price'] = price;

                        setState(() {
                          widget.model.frameOverride = mutableSelected;
                          widget.model.updateProfileThickness();
                          widget.model.refreshUI();
                        });
                      }
                    },
                  ),

                  if (zone.content == ZoneContent.singleSash ||
                      zone.content == ZoneContent.doubleSash ||
                      zone.content == ZoneContent.slidingSash) ...[
                    const SizedBox(width: 8),
                    _ContentButton(
                      label: widget.model.sashOverride != null
                          ? '${widget.model.sashOverride!['name']}'
                          : Localization.translate('اختر الظلفة (Sash)', lang),
                      icon: Icons.format_paint_rounded,
                      selected: widget.model.sashOverride != null,
                      onPressed: () async {
                        final selected = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (context) =>
                              ProfileSelectorDialog(
                                profileType: 'sash',
                                seriesId: activeSeriesForSystem?.id,
                              ),
                        );
                        if (selected != null) {
                          double price = 0.0;
                          if (widget.model.selectedDbColor != null) {
                            int colorId = widget.model.selectedDbColor!['id'];
                            final db = SqlDatabase();
                            price = await db.getSectionPrice(
                              selected['id'],
                              colorId,
                            );
                          }
                          final mutableSelected = Map<String, dynamic>.from(
                            selected,
                          );
                          mutableSelected['calculated_price'] = price;

                          setState(() {
                            widget.model.sashOverride = mutableSelected;
                            widget.model.updateAllSashThicknesses();
                          });
                        }
                      },
                    ),
                    if (zone.content == ZoneContent.slidingSash) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: zone.useClassicHandle
                            ? Localization.translate('مقبض كلاسيكي (فتح)', lang)
                            : Localization.translate('مقبض منزلق (جرار)', lang),
                        icon: Icons.sync_alt_rounded,
                        selected: zone.useClassicHandle,
                        onPressed: () {
                          setState(() {
                            widget.model.toggleSelectedZoneClassicHandle();
                          });
                        },
                      ),
                    ],
                    const SizedBox(width: 8),
                    ...(zone.content == ZoneContent.doubleSash ||
                        zone.content == ZoneContent.slidingSash
                        ? [OpenDirection.left, OpenDirection.right]
                        : OpenDirection.values)
                        .map(
                          (dir) =>
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _ContentButton(
                              label: _getDirectionName(dir),
                              icon: Icons.open_with_rounded,
                              selected: zone.openDirection == dir,
                              onPressed: () =>
                                  widget.model
                                      .setSelectedZoneOpenDirection(dir),
                            ),
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'نوع المنطقة:',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (widget.systemMode != 'sliding') ...[
                    _ContentButton(
                      label: 'فارغة',
                      icon: Icons.crop_free_rounded,
                      selected: zone.content == ZoneContent.empty,
                      onPressed: () {
                        widget.model.setSelectedZoneContent(ZoneContent.empty);
                      },
                    ),
                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'زجاج ثابت',
                      icon: Icons.window_rounded,
                      selected: zone.content == ZoneContent.fixedGlass,
                      onPressed: () {
                        widget.model.setSelectedZoneContent(
                          ZoneContent.fixedGlass,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    if (widget.model.canZoneHaveSash(zone)) ...[
                      _ContentButton(
                        label: 'ضلفة واحدة',
                        icon: Icons.door_back_door_rounded,
                        selected: zone.content == ZoneContent.singleSash,
                        onPressed: () {
                          widget.model.setSelectedZoneContent(
                            ZoneContent.singleSash,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'ضلفتان',
                        icon: Icons.garage_rounded,
                        selected: zone.content == ZoneContent.doubleSash,
                        onPressed: () {
                          widget.model.setSelectedZoneContent(
                            ZoneContent.doubleSash,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (widget.systemMode == 'mixed' && isSlidingSupported) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'منزلق 2',
                        icon: Icons.sync_alt_rounded,
                        selected:
                        zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 2,
                        onPressed: () {
                          if (widget.model.hasArchOrSlant) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                  textDirection: TextDirection.rtl,
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            widget.model.setSelectedZoneSlidingSashes(2);
                          }
                        },
                      ),
                      if (slidingSeriesName.contains('h36') ||
                          slidingSeriesName.contains('67000') ||
                          slidingSeriesName.contains('67000ld') ||
                          slidingSeriesName.contains('70kp') ||
                          slidingSeriesName.contains('hps') ||
                          slidingSeriesName.contains('tpr')) ...[
                        const SizedBox(width: 8),
                        _ContentButton(
                          label: 'منزلق 3',
                          icon: Icons.sync_alt_rounded,
                          selected:
                          zone.content == ZoneContent.slidingSash &&
                              zone.slidingSashesCount == 3,
                          onPressed: () {
                            if (widget.model.hasArchOrSlant) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                    textDirection: TextDirection.rtl,
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } else {
                              widget.model.setSelectedZoneSlidingSashes(3);
                            }
                          },
                        ),
                      ],
                      if (slidingSeriesName.contains('h36') ||
                          slidingSeriesName.contains('hps')) ...[
                        const SizedBox(width: 8),
                        _ContentButton(
                          label: 'منزلق 4',
                          icon: Icons.sync_alt_rounded,
                          selected:
                          zone.content == ZoneContent.slidingSash &&
                              zone.slidingSashesCount == 4,
                          onPressed: () {
                            if (widget.model.hasArchOrSlant) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                    textDirection: TextDirection.rtl,
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } else {
                              widget.model.setSelectedZoneSlidingSashes(4);
                            }
                          },
                        ),
                      ],
                    ],
                  ],
                  if (widget.systemMode == 'sliding' && isSlidingSupported) ...[
                    _ContentButton(
                      label: 'منزلق 2',
                      icon: Icons.sync_alt_rounded,
                      selected:
                      zone.content == ZoneContent.slidingSash &&
                          zone.slidingSashesCount == 2,
                      onPressed: () {
                        if (widget.model.hasArchOrSlant) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                textDirection: TextDirection.rtl,
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } else {
                          widget.model.setSelectedZoneSlidingSashes(2);
                        }
                      },
                    ),
                    if (slidingSeriesName.contains('h36') ||
                        slidingSeriesName.contains('67000') ||
                        slidingSeriesName.contains('67000ld') ||
                        slidingSeriesName.contains('70kp') ||
                        slidingSeriesName.contains('hps') ||
                        slidingSeriesName.contains('tpr')) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'منزلق 3',
                        icon: Icons.sync_alt_rounded,
                        selected:
                        zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 3,
                        onPressed: () {
                          if (widget.model.hasArchOrSlant) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                  textDirection: TextDirection.rtl,
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            widget.model.setSelectedZoneSlidingSashes(3);
                          }
                        },
                      ),
                    ],
                    if (slidingSeriesName.contains('h36') ||
                        slidingSeriesName.contains('hps')) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'منزلق 4',
                        icon: Icons.sync_alt_rounded,
                        selected:
                        zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 4,
                        onPressed: () {
                          if (widget.model.hasArchOrSlant) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                  textDirection: TextDirection.rtl,
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            widget.model.setSelectedZoneSlidingSashes(4);
                          }
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
            if (widget.model.activeSubZone != null &&
                (widget.model.activeSubZone!.contains('cell_') ||
                    zone.content == ZoneContent.fixedGlass)) ...[
              const SizedBox(height: 12),
              const Text(
                'مظهر القسم المحدد:',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (widget.model.activeSubZone != null &&
                        widget.model.activeSubZone!.contains('cell_') &&
                        (zone.content == ZoneContent.singleSash ||
                            zone.content == ZoneContent.doubleSash)) ...[
                      _ContentButton(
                        label:
                        zone.cellIsSash[widget.model.activeSubZone!] == true
                            ? 'دلفة داخلية (نشطة)'
                            : 'إضافة دلفة داخلية',
                        icon: Icons.window,
                        selected:
                        zone.cellIsSash[widget.model.activeSubZone!] ==
                            true,
                        onPressed: () {
                          setState(() {
                            widget.model.toggleSelectedCellSash();
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _ContentButton(
                        label:
                        zone.cellIsDoubleSash[widget
                            .model
                            .activeSubZone!] ==
                            true
                            ? 'ضلفتان داخليتان (نشطة)'
                            : 'إضافة ضلفتان داخليتان',
                        icon: Icons.window,
                        selected:
                        zone.cellIsDoubleSash[widget
                            .model
                            .activeSubZone!] ==
                            true,
                        onPressed: () {
                          setState(() {
                            widget.model.toggleSelectedCellDoubleSash();
                          });
                        },
                      ),
                      if (zone.cellIsSash[widget.model.activeSubZone!] ==
                          true ||
                          zone.cellIsDoubleSash[widget.model.activeSubZone!] ==
                              true) ...[
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            final cellKey = widget.model.activeSubZone!;
                            bool isCellSash105 = false;
                            final currentOverride =
                            zone.cellSashOverrides[cellKey];
                            if (currentOverride != null) {
                              final code =
                                  currentOverride['code']
                                      ?.toString()
                                      .toLowerCase() ??
                                      '';
                              final name =
                                  currentOverride['name']
                                      ?.toString()
                                      .toLowerCase() ??
                                      '';
                              if (code.contains('104') ||
                                  name.contains('104')) {
                                isCellSash105 = false;
                              } else if (code.contains('105') ||
                                  code.contains('porte') ||
                                  code.contains('ouvr') ||
                                  name.contains('105') ||
                                  name.contains('porte') ||
                                  name.contains('ouvr') ||
                                  name.contains('بورت')) {
                                isCellSash105 = true;
                              } else {
                                isCellSash105 = false;
                              }
                            } else {
                              isCellSash105 = zone.isSash105;
                            }

                            bool has104105Option = false;
                            if (activeSeriesForSystem != null) {
                              for (var sec in activeSeriesForSystem!.sections) {
                                if (sec.code.contains('104') ||
                                    sec.code.contains('105') ||
                                    sec.name.contains('104') ||
                                    sec.name.contains('105')) {
                                  has104105Option = true;
                                  break;
                                }
                              }
                            }

                            if (!has104105Option) {
                              return const SizedBox.shrink();
                            }

                            return _ContentButton(
                              label: isCellSash105
                                  ? 'الظلفة 105 (صندوق باب)'
                                  : 'الظلفة 104 (نافذة)',
                              icon: Icons.swap_horiz,
                              selected: true,
                              onPressed: () async {
                                await widget.model.toggleCellSashType104105(
                                  cellKey,
                                );
                                setState(() {});
                              },
                            );
                          },
                        ),
                        Builder(
                          builder: (context) {
                            final cellKey = widget.model.activeSubZone!;
                            final isDouble =
                                zone.cellIsDoubleSash[cellKey] == true;
                            final currentDir = () {
                              final currentOverride =
                              zone.cellSashOverrides[cellKey];
                              final defaultDir = isDouble
                                  ? OpenDirection.right
                                  : OpenDirection.left;
                              if (currentOverride != null &&
                                  currentOverride['openDirection'] != null) {
                                final dirStr = currentOverride['openDirection']
                                    .toString();
                                return OpenDirection.values.firstWhere(
                                      (d) => d.name == dirStr,
                                  orElse: () => defaultDir,
                                );
                              }
                              return defaultDir;
                            }();

                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ...(isDouble
                                    ? [
                                  OpenDirection.left,
                                  OpenDirection.right,
                                ]
                                    : OpenDirection.values)
                                    .map(
                                      (dir) =>
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _ContentButton(
                                          label: _getDirectionName(dir),
                                          icon: Icons.open_with_rounded,
                                          selected: currentDir == dir,
                                          onPressed: () {
                                            setState(() {
                                              widget.model
                                                  .setCellSashOpenDirection(
                                                cellKey,
                                                dir,
                                              );
                                            });
                                          },
                                        ),
                                      ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getStructureName(GlassStructure s) {
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    switch (s) {
      case GlassStructure.simple:
        return Localization.translate('عادي', lang);
      case GlassStructure.double:
        return Localization.translate('مزدوج', lang);
      case GlassStructure.closed:
        return Localization.translate('بانو', lang);
    }
  }

  String _getFinishName(GlassFinish f) {
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    String name = '';
    switch (f) {
      case GlassFinish.clair:
        name = 'شفاف';
        break;
      case GlassFinish.stopSol:
        name = 'ستوبسول';
        break;
      case GlassFinish.sable:
        name = 'صابلي';
        break;
      case GlassFinish.delta:
        name = 'دلتا';
        break;
      case GlassFinish.tuC:
        name = 'تيسي';
        break;
      case GlassFinish.nevada:
        name = 'نيفادا';
        break;
      case GlassFinish.cuisine:
        name = 'مطبخ';
        break;
      case GlassFinish.aFleur:
        name = 'مورد';
        break;
      case GlassFinish.paneauSandwitch:
        name = 'بانو';
        break;
      case GlassFinish.resine:
        name = 'ارزين';
        break;
      case GlassFinish.plexyGlass:
        name = 'بليكسي';
        break;
      case GlassFinish.paneauSandwitchDecore:
        name = 'بانو ديكور';
        break;
      case GlassFinish.bardage:
        name = 'بارداش';
        break;
      case GlassFinish.moussa:
        name = 'موسى';
        break;
      case GlassFinish.harari:
        name = 'حراري';
        break;
      case GlassFinish.vitrageArme:
        name = 'زجاج مسلح';
        break;
    }
    return Localization.translate(name, lang);
  }

  String _getColorName(GlassColor c) {
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    String name = '';
    switch (c) {
      case GlassColor.transparent:
        name = 'شفاف';
        break;
      case GlassColor.blue:
        name = 'أزرق';
        break;
      case GlassColor.brown:
        name = 'بني';
        break;
      case GlassColor.green:
        name = 'أخضر';
        break;
      case GlassColor.gray:
        name = 'رمادي';
        break;
      case GlassColor.grayAgc:
        name = 'رمادي بلجيكي';
        break;
      case GlassColor.blueAgc:
        name = 'ازرق بلجيكي';
        break;
    }
    return Localization.translate(name, lang);
  }

  String _getClosedColoreName(ClosedGlassColor d) {
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    String name = '';
    switch (d) {
      case ClosedGlassColor.transparent:
        name = 'شفاف';
        break;
      case ClosedGlassColor.white:
        name = 'ابيض';
        break;
      case ClosedGlassColor.grisClair:
        name = 'رمادي فاتح';
        break;
      case ClosedGlassColor.fbmfonce:
        name = 'خشبي داكن';
        break;
      case ClosedGlassColor.grissoris:
        name = 'رمادي داكن';
        break;
      case ClosedGlassColor.black:
        name = 'اسود';
        break;
      case ClosedGlassColor.beige:
        name = 'باج';
        break;
      case ClosedGlassColor.fbmClair:
        name = 'خشبي فاتح';
        break;
      case ClosedGlassColor.opaque:
        name = 'عاتم';
        break;
      case ClosedGlassColor.marberier:
        name = 'رخامي';
        break;
    }
    return Localization.translate(name, lang);
  }

  String _getDirectionName(OpenDirection d) {
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    String name = '';
    switch (d) {
      case OpenDirection.left:
        name = 'يسار';
        break;
      case OpenDirection.right:
        name = 'يمين';
        break;
      case OpenDirection.top:
        name = 'أعلى';
        break;
      case OpenDirection.bottom:
        name = 'أسفل';
        break;
    }
    return Localization.translate(name, lang);
  }

  List<Widget> _arrangeInTwoRows(List<Widget> rawItems) {
    // Filter out SizedBox widgets that were used as spacers in the single-row layout
    final items = rawItems.where((w) => w is! SizedBox).toList();
    if (items.isEmpty) return [];

    List<Widget> row1 = [];
    List<Widget> row2 = [];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (row1.length <= row2.length) {
        if (row1.isNotEmpty) {
          row1.add(const SizedBox(width: 8));
        }
        row1.add(item);
      } else {
        if (row2.isNotEmpty) {
          row2.add(const SizedBox(width: 8));
        }
        row2.add(item);
      }
    }

    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: row1),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: row2),
        ],
      ),
    ];
  }

  Widget _buildInteractiveBottomPanel(BuildContext context) {
    final hasSelection = widget.model.selectedZone != null;
    final isMullionSelected =
        widget.model.selection.type == SelectionType.mullion;

    // ── إذا تم تحديد الستار → اعرض لوحة الستار ──
    if (_isShutterSelected && widget.model.hasShutter) {
      return _buildShutterBottomPanel(context);
    }

    // A drawing selection opens the panel automatically. The chevron remains
    // available to open it manually when nothing is selected.
    final showExpanded = _isBottomPanelExpanded;

    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Available before selecting a zone too: choose a type, then tap
            // the desired frame in the drawing.
            if (!showExpanded)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isBottomPanelExpanded = true;
                  });
                },
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: Colors.blue.shade700,
                      size: 22,
                    ),
                  ),
                ),
              ),

            if (showExpanded) ...[
              GestureDetector(
                onTap: () => setState(() {
                  _isBottomPanelExpanded = false;
                }),
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.blue.shade700,
                      size: 22,
                    ),
                  ),
                ),
              ),
              if (hasSelection) ...[
              // Tier 1: Horizontal Scrollable Tabs (شائع | إطار | ورقة | عامود | زجاج / حشوات)
              _buildTier1TabBar(isMullionSelected),
              const Divider(height: 1, thickness: 0.5),
              // Tier 2: Horizontal Scrollable Action Options (Two rows grid)
              Container(
                height: 110,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: _HorizontalWheelScrollArea(
                  builder: (context, controller) =>
                      SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _arrangeInTwoRows(
                            _buildTier2Options(context, isMullionSelected),
                          ),
                        ),
                      ),
                ),
              ),
              ] else
                _buildZoneContentPaintPicker(context),
            ] else
              ...[
                // Collapsed state: Show original Status Bar & Calculations
                _buildCollapsedStatusBar(context),
              ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // لوحة خصائص الستار السفلية
  // ═══════════════════════════════════════════════════════════════════
  /// Compact, deliberately manual content picker shown when no frame is
  /// selected. Choosing an item arms the paint tool; the next click on a
  /// frame applies the type instead of opening the panel automatically.
  Widget _buildZoneContentPaintPicker(BuildContext context) {
    final lang =
        Provider.of<AppSettingsProvider>(context, listen: false).language;
    final canUseOpening = widget.systemMode != 'sliding';
    final canUseSliding =
        widget.systemMode == 'mixed' || widget.systemMode == 'sliding';

    Widget option(
      String label,
      IconData icon,
      ZoneContent content, {
      int? slidingSashesCount,
    }) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: _ContentButton(
          label: Localization.translate(label, lang),
          icon: icon,
          selected: false,
          onPressed: () {
            _startPaintbrushMode(
              zoneContent: content,
              slidingSashesCount: slidingSashesCount,
            );
            setState(() {
              _isBottomPanelExpanded = false;
              _isShutterSelected = false;
            });
          },
        ),
      );
    }

    return Container(
      height: 100,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Localization.translate('اختر النوع ثم اضغط على الإطار', lang),
            style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _HorizontalWheelScrollArea(
              builder: (context, controller) => SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    option('فارغة', Icons.crop_free_rounded, ZoneContent.empty),
                    if (canUseOpening)
                      option(
                        'زجاج ثابت',
                        Icons.window_rounded,
                        ZoneContent.fixedGlass,
                      ),
                    if (canUseOpening)
                      option(
                        'ضلفة واحدة',
                        Icons.door_back_door_rounded,
                        ZoneContent.singleSash,
                      ),
                    if (canUseOpening)
                      option(
                        'ضلفتان',
                        Icons.garage_rounded,
                        ZoneContent.doubleSash,
                      ),
                    if (canUseSliding)
                      option(
                        'منزلق 2',
                        Icons.sync_alt_rounded,
                        ZoneContent.slidingSash,
                        slidingSashesCount: 2,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShutterBottomPanel(BuildContext context) {
    final isMullionSelected =
        widget.model.selection.type == SelectionType.mullion;
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Main Tab Bar showing "الستار (Volet)" selected ──
            _buildTier1TabBar(isMullionSelected),
            const Divider(height: 1, thickness: 0.5),
            // ── تبويبات الستار (Tier 1 of Shutter) ──
            _buildShutterTier1TabBar(),
            const Divider(height: 1, thickness: 0.5),
            // ── محتوى التبويب (Tier 2) ──
            SizedBox(
              height: 110,
              child: _loadingShutterOptions
                  ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
                  : _HorizontalWheelScrollArea(
                builder: (context, controller) =>
                    SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children:
                        (_activeShutterTab == 0 || _activeShutterTab == 4)
                            ? _buildShutterTier2Options(context)
                            : _arrangeInTwoRows(
                          _buildShutterTier2Options(context),
                        ),
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShutterTier1TabBar() {
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    final tabs = [
      {'id': 0, 'label': 'شائع', 'icon': Icons.tune_rounded},
      {'id': 1, 'label': 'الصندوق', 'icon': Icons.inbox_rounded},
      {'id': 2, 'label': 'الشفرات', 'icon': Icons.view_week_rounded},
      {'id': 3, 'label': 'السكك', 'icon': Icons.linear_scale_rounded},
      {'id': 4, 'label': 'نوع الستار', 'icon': Icons.settings_rounded},
    ];

    return SizedBox(
      height: 44,
      child: _HorizontalWheelScrollArea(
        builder: (context, controller) =>
            ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final id = tab['id'] as int;
                final isSelected = _activeShutterTab == id;
                return InkWell(
                  onTap: () => setState(() => _activeShutterTab = id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected
                              ? Colors.orange.shade700
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tab['icon'] as IconData,
                          size: 15,
                          color: isSelected
                              ? Colors.orange.shade700
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          Localization.translate(tab['label'] as String, lang),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.orange.shade700
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }

  List<Widget> _buildShutterTier2Options(BuildContext context) {
    switch (_activeShutterTab) {
      case 0: // شائع
        return _buildShutterCommonOptions(context);
      case 1: // الصندوق
        return _buildShutterCaissonOptions(context);
      case 2: // الشفرات
        return _buildShutterLamesOptions2(context);
      case 3: // السكك
        return _buildShutterCoulisseOptions(context);
      case 4: // نوع الستار
        return _buildShutterMechanismOptions(context);
      default:
        return [];
    }
  }

  // تبويب شائع: تفعيل/إلغاء الستار + Caisson Tunnel
  List<Widget> _buildShutterCommonOptions(BuildContext context) {
    final items = <Widget>[];

    // تفعيل/إلغاء الستار
    items.add(
      _ShutterChip(
        label: 'الستار مفعّل',
        icon: Icons.layers_rounded,
        selected: widget.model.hasShutter,
        color: Colors.orange,
        onTap: () {
          setState(() {
            widget.model.hasShutter = !widget.model.hasShutter;
            if (!widget.model.hasShutter) _isShutterSelected = false;
            widget.model.refreshUI();
          });
          if (widget.model.hasShutter) {
            unawaited(widget.model.updateShutterDefaultsIfNeeded());
          }
        },
      ),
    );
    items.add(const SizedBox(width: 8));

    // صندوق نفق
    items.add(
      _ShutterChip(
        label: 'صندوق نفق',
        icon: Icons.horizontal_rule_rounded,
        selected: widget.model.isCaissonTunnel,
        color: Colors.deepPurple,
        onTap: () {
          setState(() {
            widget.model.toggleCaissonTunnel(!widget.model.isCaissonTunnel);
            widget.model.refreshUI();
          });
        },
      ),
    );
    items.add(const SizedBox(width: 8));

    // غطاء جانبي
    items.add(
      _ShutterChip(
        label: 'غطاء جانبي',
        icon: Icons.border_left_rounded,
        selected: widget.model.hasSideCovers,
        color: Colors.teal,
        onTap: () {
          setState(() {
            widget.model.hasSideCovers = !widget.model.hasSideCovers;
            widget.model.refreshUI();
          });
        },
      ),
    );

    return items;
  }

  // تبويب الصندوق
  List<Widget> _buildShutterCaissonOptions(BuildContext context) {
    if (_shutterCaissonOptions.isEmpty) {
      return [
        const Center(
          child: Text(
            'لا توجد صناديق في قاعدة البيانات',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final current = widget.model.componentOverrides['الصندوق (Caisson)'];
    final currentId = current?['id'];
    return _shutterCaissonOptions.map((opt) {
      final isSelected = currentId != null && opt['id'] == currentId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterChip(
            label: opt['name']?.toString() ?? '',
            icon: Icons.inbox_rounded,
            selected: isSelected,
            color: Colors.indigo,
            onTap: () {
              final mutable = Map<String, dynamic>.from(opt);
              mutable['calculated_price'] =
                  (opt['price_dzd'] ?? opt['price'] ?? 0.0).toDouble();
              setState(() {
                widget.model.componentOverrides['الصندوق (Caisson)'] = mutable;
                widget.model.refreshUI();
              });
              unawaited(widget.model.updateShutterDefaultsIfNeeded());
            },
          ),
          const SizedBox(width: 8),
        ],
      );
    }).toList();
  }

  // تبويب الشفرات
  List<Widget> _buildShutterLamesOptions2(BuildContext context) {
    if (_shutterLamesOptions.isEmpty) {
      return [
        const Center(
          child: Text(
            'لا توجد شفرات في قاعدة البيانات',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final current = widget.model.componentOverrides['الشرائح (Lames)'];
    final currentId = current?['id'];
    return _shutterLamesOptions.map((opt) {
      final isSelected = currentId != null && opt['id'] == currentId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterChip(
            label: opt['name']?.toString() ?? '',
            icon: Icons.view_week_rounded,
            selected: isSelected,
            color: Colors.brown,
            onTap: () {
              final mutable = Map<String, dynamic>.from(opt);
              mutable['calculated_price'] =
                  (opt['price_dzd'] ?? opt['price'] ?? 0.0).toDouble();
              setState(() {
                widget.model.componentOverrides['الشرائح (Lames)'] = mutable;
                widget.model.shutterLame =
                    mutable['name']?.toString() ?? widget.model.shutterLame;
                widget.model.refreshUI();
              });
              // X3D / Extrudé chooses its compatible axis and motor as soon
              // as the blade changes, not only after reopening the table.
              unawaited(widget.model.updateShutterDefaultsIfNeeded());
            },
          ),
          const SizedBox(width: 8),
        ],
      );
    }).toList();
  }

  // تبويب السكك
  List<Widget> _buildShutterCoulisseOptions(BuildContext context) {
    if (_shutterCoulisseOptions.isEmpty) {
      return [
        const Center(
          child: Text(
            'لا توجد سكك في قاعدة البيانات',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final current = widget.model.componentOverrides['السكك (Coulisses)'];
    final currentId = current?['id'];
    return _shutterCoulisseOptions.map((opt) {
      final isSelected = currentId != null && opt['id'] == currentId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterChip(
            label: opt['name']?.toString() ?? '',
            icon: Icons.linear_scale_rounded,
            selected: isSelected,
            color: Colors.cyan.shade800,
            onTap: () {
              final mutable = Map<String, dynamic>.from(opt);
              mutable['calculated_price'] =
                  (opt['price_dzd'] ?? opt['price'] ?? 0.0).toDouble();
              setState(() {
                widget.model.componentOverrides['السكك (Coulisses)'] = mutable;
                widget.model.refreshUI();
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      );
    }).toList();
  }

  // تبويب نوع الستار (الآلية)
  List<Widget> _buildShutterMechanismOptions(BuildContext context) {
    final items = <Widget>[];
    final mechanisms = [
      {'value': 'حزام', 'label': 'حزام', 'icon': Icons.radio_button_unchecked},
      {
        'value': 'مانيفال',
        'label': 'مانيفال',
        'icon': Icons.settings_backup_restore_rounded,
      },
      {'value': 'محرك', 'label': 'محرك', 'icon': Icons.electric_bolt_rounded},
    ];
    for (final mech in mechanisms) {
      final val = mech['value'] as String;
      final isSelected =
          widget.model.shutterMechanism == val ||
              (val == 'مانيفال' &&
                  (widget.model.shutterMechanism == 'منايفال' ||
                      widget.model.shutterMechanism == 'مانيفر'));
      items.add(
        _ShutterChip(
          label: mech['label'] as String,
          icon: mech['icon'] as IconData,
          selected: isSelected,
          color: Colors.deepOrange,
          onTap: () {
            setState(() {
              widget.model.shutterMechanism = val;
              widget.model.refreshUI();
            });
            unawaited(widget.model.updateShutterDefaultsIfNeeded());
          },
        ),
      );
      items.add(const SizedBox(width: 8));
    }

    if (widget.model.shutterMechanism == 'محرك') {
      items.add(
        const VerticalDivider(width: 16, thickness: 1, indent: 8, endIndent: 8),
      );
      items.add(const SizedBox(width: 8));

      // قاطعة (Interrupteur)
      items.add(
        _ShutterChip(
          label: 'قاطعة (Interrupteur)',
          icon: Icons.power,
          selected: widget.model.motorHasInterrupteur,
          color: Colors.blue,
          onTap: () {
            setState(() {
              widget.model.motorHasInterrupteur =
              !widget.model.motorHasInterrupteur;
              widget.model.refreshUI();
            });
          },
        ),
      );
      items.add(const SizedBox(width: 8));

      // جهاز تحكم (Télécommande)
      items.add(
        _ShutterChip(
          label: 'جهاز تحكم (Télécommande)',
          icon: Icons.settings_remote,
          selected: widget.model.motorHasTelecommande,
          color: Colors.blue,
          onTap: () {
            setState(() {
              widget.model.motorHasTelecommande =
              !widget.model.motorHasTelecommande;
              widget.model.refreshUI();
            });
          },
        ),
      );
      items.add(const SizedBox(width: 8));
    }
    return items;
  }

  Widget _buildTier1TabBar(bool isMullionSelected) {
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    final List<Map<String, dynamic>> tabs = [
      {'id': 0, 'label': 'شائع', 'icon': Icons.tune_rounded},
      {'id': 1, 'label': 'إطار', 'icon': Icons.border_outer_rounded},
      {'id': 2, 'label': 'ورقة', 'icon': Icons.door_back_door_rounded},
      if (isMullionSelected)
        {'id': 3, 'label': 'عامود', 'icon': Icons.vertical_split_rounded},
      {'id': 4, 'label': 'زجاج / حشوات', 'icon': Icons.grid_on_rounded},
      {'id': 5, 'label': 'مقابض', 'icon': Icons.vpn_key_rounded},
      if (widget.model.hasShutter)
        {'id': 6, 'label': 'الستار (Volet)', 'icon': Icons.layers_rounded},
    ];

    return SizedBox(
      height: 44,
      child: _HorizontalWheelScrollArea(
        builder: (context, controller) =>
            ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final id = tab['id'] as int;
                final isSelected = _isShutterSelected
                    ? (id == 6)
                    : (_activeBottomTab == id);

                return InkWell(
                  onTap: () {
                    setState(() {
                      _isBottomPanelExpanded = true;
                      if (id == 6) {
                        _isShutterSelected = true;
                        _activeShutterTab = 0;
                        _loadShutterOptions();
                      } else {
                        _isShutterSelected = false;
                        _activeBottomTab = id;
                        if (widget.model.selectedZone == null &&
                            widget.model.zones.isNotEmpty) {
                          widget.model.selection = SelectionInfo.zone(
                            widget.model.zones.first.id,
                          );
                        }
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? Colors.blue : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tab['icon'] as IconData,
                          size: 16,
                          color: isSelected
                              ? Colors.blue
                              : (Theme
                              .of(context)
                              .brightness == Brightness.dark
                              ? Colors.white54
                              : Colors.grey.shade600),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          Localization.translate(tab['label'] as String, lang),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.blue
                                : (Theme
                                .of(context)
                                .brightness == Brightness.dark
                                ? Colors.white60
                                : Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }

  List<Widget> _buildTier2Options(BuildContext context,
      bool isMullionSelected,) {
    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;
    final zone = widget.model.selectedZone;
    if (zone == null) return [];

    String seriesName = activeSeriesForSystem != null
        ? activeSeriesForSystem!.name.toLowerCase()
        : '';
    String slidingSeriesName = widget.model.activeSlidingSeries != null
        ? widget.model.activeSlidingSeries!.name.toLowerCase()
        : seriesName;

    List<Widget> children = [];

    switch (_activeBottomTab) {
      case 0: // شائع (Common tools)
        if (widget.systemMode != 'sliding') {
          // 1. Split horizontal
          children.add(
            _ContentButton(
              label: Localization.translate('تقسيم أفقي', lang),
              icon: Icons.horizontal_split_rounded,
              selected: false,
              onPressed: () {
                _showSplitDialog(context, true);
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          // 2. Split vertical
          children.add(
            _ContentButton(
              label: Localization.translate('تقسيم عمودي', lang),
              icon: Icons.vertical_split_rounded,
              selected: false,
              onPressed: () {
                _showSplitDialog(context, false);
              },
            ),
          );
          children.add(const SizedBox(width: 8));
        }

        // 3. Reset Zoom
        if (!_isWindowsDesktop) {
          children.add(
            _ContentButton(
              label: Localization.translate('إعادة التكبير', lang),
              icon: Icons.zoom_out_map_rounded,
              selected: false,
              onPressed: _resetDrawingZoom,
            ),
          );
          children.add(const SizedBox(width: 8));
        }

        // 4. Zone contents
        children.add(
          _ContentButton(
            label: Localization.translate('فارغة', lang),
            icon: Icons.crop_free_rounded,
            selected: zone.content == ZoneContent.empty,
            onPressed: () {
              widget.model.setSelectedZoneContent(ZoneContent.empty);
            },
          ),
        );
        children.add(const SizedBox(width: 8));

        if (widget.systemMode != 'sliding') {
          children.add(
            _ContentButton(
              label: Localization.translate('زجاج ثابت', lang),
              icon: Icons.window_rounded,
              selected: zone.content == ZoneContent.fixedGlass,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.fixedGlass);
              },
            ),
          );
          children.add(const SizedBox(width: 8));
        }

        if (widget.systemMode != 'sliding' &&
            widget.model.canZoneHaveSash(zone)) {
          children.add(
            _ContentButton(
              label: Localization.translate('ضلفة واحدة', lang),
              icon: Icons.door_back_door_rounded,
              selected: zone.content == ZoneContent.singleSash,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.singleSash);
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: Localization.translate('ضلفتان', lang),
              icon: Icons.garage_rounded,
              selected: zone.content == ZoneContent.doubleSash,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.doubleSash);
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          if (widget.systemMode == 'mixed' && isSlidingSupported) {
            children.add(
              _ContentButton(
                label: Localization.translate('منزلق 2', lang),
                icon: Icons.sync_alt_rounded,
                selected:
                zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == 2,
                onPressed: () {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          Localization.translate(
                            'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                            lang,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    widget.model.setSelectedZoneSlidingSashes(2);
                  }
                },
              ),
            );

            if (slidingSeriesName.contains('h36') ||
                slidingSeriesName.contains('67000') ||
                slidingSeriesName.contains('67000ld') ||
                slidingSeriesName.contains('70kp') ||
                slidingSeriesName.contains('hps') ||
                slidingSeriesName.contains('tpr')) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: Localization.translate('منزلق 3', lang),
                  icon: Icons.sync_alt_rounded,
                  selected:
                  zone.content == ZoneContent.slidingSash &&
                      zone.slidingSashesCount == 3,
                  onPressed: () {
                    if (widget.model.hasArchOrSlant) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                              lang,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } else {
                      widget.model.setSelectedZoneSlidingSashes(3);
                    }
                  },
                ),
              );
            }

            if (slidingSeriesName.contains('h36') ||
                slidingSeriesName.contains('hps')) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: Localization.translate('منزلق 4', lang),
                  icon: Icons.sync_alt_rounded,
                  selected:
                  zone.content == ZoneContent.slidingSash &&
                      zone.slidingSashesCount == 4,
                  onPressed: () {
                    if (widget.model.hasArchOrSlant) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                              lang,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } else {
                      widget.model.setSelectedZoneSlidingSashes(4);
                    }
                  },
                ),
              );
            }
          }
        } else if (isSlidingSupported) {
          children.add(
            _ContentButton(
              label: 'منزلق 2',
              icon: Icons.sync_alt_rounded,
              selected:
              zone.content == ZoneContent.slidingSash &&
                  zone.slidingSashesCount == 2,
              onPressed: () {
                if (widget.model.hasArchOrSlant) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                        textDirection: TextDirection.rtl,
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else {
                  widget.model.setSelectedZoneSlidingSashes(2);
                }
              },
            ),
          );

          if (slidingSeriesName.contains('h36') ||
              slidingSeriesName.contains('67000') ||
              slidingSeriesName.contains('67000ld') ||
              slidingSeriesName.contains('70kp') ||
              slidingSeriesName.contains('hps') ||
              slidingSeriesName.contains('tpr')) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: 'منزلق 3',
                icon: Icons.sync_alt_rounded,
                selected:
                zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == 3,
                onPressed: () {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    widget.model.setSelectedZoneSlidingSashes(3);
                  }
                },
              ),
            );
          }

          if (slidingSeriesName.contains('h36') ||
              slidingSeriesName.contains('hps')) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: 'منزلق 4',
                icon: Icons.sync_alt_rounded,
                selected:
                zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == 4,
                onPressed: () {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    widget.model.setSelectedZoneSlidingSashes(4);
                  }
                },
              ),
            );
          }
        }
        if (!widget.model.isPVC &&
            widget.model.systemMode != 'sliding' &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash)) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.hasSashPlintheBottom
                  ? 'حذف بلانت الضلفة'
                  : 'إضافة بلانت للضلفة',
              icon: Icons.border_bottom_rounded,
              selected: zone.hasSashPlintheBottom,
              onPressed: () {
                setState(() {
                  widget.model.toggleSelectedZoneSashPlintheBottom();
                });
              },
            ),
          );
        }
        break;

      case 1: // إطار (Frame settings)
        final bool isSliding =
            widget.systemMode == 'sliding' ||
                (widget.systemMode == 'mixed' &&
                    zone != null &&
                    zone.content == ZoneContent.slidingSash);
        if (_frameProfiles.isEmpty) {
          children.add(
            Text(
              Localization.translate(
                'لا توجد إطارات متوفرة لهذه السلسلة',
                lang,
              ),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        } else {
          for (var item in _frameProfiles) {
            final codeStr =
            (item['code'] != null && item['code']
                .toString()
                .isNotEmpty)
                ? '${item['code']} - '
                : '';
            final nameStr = item['name'] ?? 'بدون اسم';
            final label = '$codeStr$nameStr';
            final isSelected = isSliding
                ? (widget.model.slidingFrameOverride != null &&
                widget.model.slidingFrameOverride!['id'] == item['id'])
                : (widget.model.frameOverride != null &&
                widget.model.frameOverride!['id'] == item['id']);

            children.add(
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ProfileButton(
                  label: label,
                  code: item['code']?.toString(),
                  imagePath: item['image_path']?.toString(),
                  selected: isSelected,
                  onPressed: () async {
                    double price = 0.0;
                    if (widget.model.selectedDbColor != null) {
                      int colorId = widget.model.selectedDbColor!['id'];
                      final db = SqlDatabase();
                      price = await db.getSectionPrice(item['id'], colorId);
                    }
                    final mutableSelected = Map<String, dynamic>.from(item);
                    mutableSelected['calculated_price'] = price;
                    setState(() {
                      if (isSliding) {
                        widget.model.slidingFrameOverride = mutableSelected;
                      } else {
                        widget.model.frameOverride = mutableSelected;
                        widget.model.selectedFrameCode = mutableSelected['code']
                            ?.toString();
                      }
                      widget.model.updateProfileThickness();
                      widget.model.refreshUI();
                    });
                    await widget.model.syncFrameReinforcement();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            );
          }
        }

        // زر الغطاء الجانبي (Side Cover toggle)
        children.add(const SizedBox(width: 8));
        children.add(
          _ContentButton(
            label: widget.model.hasSideCovers
                ? Localization.translate('إزالة غطاء جانبي', lang)
                : Localization.translate('إضافة غطاء جانبي', lang),
            icon: widget.model.hasSideCovers
                ? Icons.border_clear_rounded
                : Icons.border_outer_rounded,
            selected: widget.model.hasSideCovers,
            onPressed: () async {
              await widget.model.toggleSideCovers(!widget.model.hasSideCovers);
              setState(() {});
            },
          ),
        );
        break;

      case 2: // ورقة (Sash settings)
        final bool isSliding =
            widget.systemMode == 'sliding' ||
                (widget.systemMode == 'mixed' &&
                    zone != null &&
                    zone.content == ZoneContent.slidingSash);
        if (!isSliding) {
          children.add(
            _ContentButton(
              label: Localization.translate('ضلفة واحدة', lang),
              icon: Icons.door_back_door_rounded,
              selected: zone.content == ZoneContent.singleSash,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.singleSash);
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: Localization.translate('ضلفتان', lang),
              icon: Icons.garage_rounded,
              selected: zone.content == ZoneContent.doubleSash,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.doubleSash);
              },
            ),
          );
          children.add(const SizedBox(width: 8));
        }

        if (_sashProfiles.isEmpty) {
          children.add(
            Text(
              Localization.translate('لا توجد درف متوفرة لهذه السلسلة', lang),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        } else if (isSliding) {
          final lateralProfiles = _sashProfiles.where((s) {
            final name = s['name'].toString().toLowerCase();
            final type = s['type'].toString().toLowerCase();
            final code = s['code'].toString().toLowerCase();
            return type.contains('lateral') ||
                type.contains('جانبي') ||
                name.contains('lateral') ||
                name.contains('جانبي') ||
                code.contains('104') ||
                code.contains('108');
          }).toList();

          final centralProfiles = _sashProfiles.where((s) {
            final name = s['name'].toString().toLowerCase();
            final type = s['type'].toString().toLowerCase();
            final code = s['code'].toString().toLowerCase();
            return type.contains('central') ||
                type.contains('وسطي') ||
                name.contains('central') ||
                name.contains('وسطي') ||
                code.contains('105') ||
                code.contains('107');
          }).toList();

          bool isLateralSelected(Map<String, dynamic> item) {
            bool isLateralReinforced = widget.model.zones.any(
                  (z) =>
              z.slidingMontantReinforced['lateral_0'] == true ||
                  z.slidingMontantReinforced['lateral_1'] == true,
            );
            final String code = item['code']?.toString() ?? '';
            final String name = item['name']?.toString().toLowerCase() ?? '';
            final String type = item['type']?.toString().toLowerCase() ?? '';
            bool itemIsReinforced =
                code.endsWith('108') ||
                    name.contains('معزز') ||
                    name.contains('renforc') ||
                    type.contains('renforc');
            return isLateralReinforced == itemIsReinforced;
          }

          bool isCentralSelected(Map<String, dynamic> item) {
            bool isCentralReinforced = widget.model.zones.any(
                  (z) =>
                  z.slidingMontantReinforced.entries.any(
                        (e) => e.key.startsWith('central_') && e.value == true,
                  ),
            );
            final String code = item['code']?.toString() ?? '';
            final String name = item['name']?.toString().toLowerCase() ?? '';
            final String type = item['type']?.toString().toLowerCase() ?? '';
            bool itemIsReinforced =
                code.endsWith('107') ||
                    name.contains('معزز') ||
                    name.contains('renforc') ||
                    type.contains('renforc');
            return isCentralReinforced == itemIsReinforced;
          }

          void selectLateral(Map<String, dynamic> item) async {
            final String code = item['code']?.toString() ?? '';
            final String name = item['name']?.toString().toLowerCase() ?? '';
            final String type = item['type']?.toString().toLowerCase() ?? '';
            bool isRenforce =
                code.endsWith('108') ||
                    name.contains('معزز') ||
                    name.contains('renforc') ||
                    type.contains('renforc');

            double price = 0.0;
            if (widget.model.selectedDbColor != null) {
              int colorId = widget.model.selectedDbColor!['id'];
              final db = SqlDatabase();
              price = await db.getSectionPrice(item['id'], colorId);
            }
            final mutableSelected = Map<String, dynamic>.from(item);
            mutableSelected['calculated_price'] = price;

            setState(() {
              for (var z in widget.model.zones) {
                if (z.content == ZoneContent.slidingSash) {
                  z.slidingMontantReinforced['lateral_0'] = isRenforce;
                  z.slidingMontantReinforced['lateral_1'] = isRenforce;
                }
              }
              widget.model.componentOverrides['قائم جانبي (Sash Lateral)'] =
                  mutableSelected;
              widget.model.refreshUI();
            });
          }

          void selectCentral(Map<String, dynamic> item) async {
            final String code = item['code']?.toString() ?? '';
            final String name = item['name']?.toString().toLowerCase() ?? '';
            final String type = item['type']?.toString().toLowerCase() ?? '';
            bool isRenforce =
                code.endsWith('107') ||
                    name.contains('معزز') ||
                    name.contains('renforc') ||
                    type.contains('renforc');

            double price = 0.0;
            if (widget.model.selectedDbColor != null) {
              int colorId = widget.model.selectedDbColor!['id'];
              final db = SqlDatabase();
              price = await db.getSectionPrice(item['id'], colorId);
            }
            final mutableSelected = Map<String, dynamic>.from(item);
            mutableSelected['calculated_price'] = price;

            setState(() {
              for (var z in widget.model.zones) {
                if (z.content == ZoneContent.slidingSash) {
                  final int sashes = z.slidingSashesCount > 0
                      ? z.slidingSashesCount
                      : 2;
                  final int centralCount = (sashes * 2) - 2;
                  for (int s = 0; s < centralCount; s++) {
                    z.slidingMontantReinforced['central_$s'] = isRenforce;
                  }
                }
              }
              widget.model.componentOverrides['قائم وسطي (Sash Central)'] =
                  mutableSelected;
              widget.model.refreshUI();
            });
          }

          // Add Lateral label
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                Localization.translate('الجانبي (Lateral):', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Colors.blue,
                ),
              ),
            ),
          );

          for (var item in lateralProfiles) {
            final codeStr =
            (item['code'] != null && item['code']
                .toString()
                .isNotEmpty)
                ? '${item['code']} - '
                : '';
            final nameStr = item['name'] ?? 'بدون اسم';
            final label = '$codeStr$nameStr';
            final isSelected = isLateralSelected(item);

            children.add(
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ProfileButton(
                  label: label,
                  code: item['code']?.toString(),
                  imagePath: item['image_path']?.toString(),
                  selected: isSelected,
                  onPressed: () => selectLateral(item),
                ),
              ),
            );
          }

          children.add(const SizedBox(width: 12));

          // Add Central label
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                Localization.translate('الوسطي (Central):', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Colors.blue,
                ),
              ),
            ),
          );

          for (var item in centralProfiles) {
            final codeStr =
            (item['code'] != null && item['code']
                .toString()
                .isNotEmpty)
                ? '${item['code']} - '
                : '';
            final nameStr = item['name'] ?? 'بدون اسم';
            final label = '$codeStr$nameStr';
            final isSelected = isCentralSelected(item);

            children.add(
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ProfileButton(
                  label: label,
                  code: item['code']?.toString(),
                  imagePath: item['image_path']?.toString(),
                  selected: isSelected,
                  onPressed: () => selectCentral(item),
                ),
              ),
            );
          }
        } else {
          for (var item in _sashProfiles) {
            final codeStr =
            (item['code'] != null && item['code']
                .toString()
                .isNotEmpty)
                ? '${item['code']} - '
                : '';
            final nameStr = item['name'] ?? 'بدون اسم';
            final label = '$codeStr$nameStr';
            final isSelected =
                widget.model.sashOverride != null &&
                    widget.model.sashOverride!['id'] == item['id'];

            children.add(
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ProfileButton(
                  label: label,
                  code: item['code']?.toString(),
                  imagePath: item['image_path']?.toString(),
                  selected: isSelected,
                  onPressed: () async {
                    double price = 0.0;
                    if (widget.model.selectedDbColor != null) {
                      int colorId = widget.model.selectedDbColor!['id'];
                      final db = SqlDatabase();
                      price = await db.getSectionPrice(item['id'], colorId);
                    }
                    final mutableSelected = Map<String, dynamic>.from(item);
                    mutableSelected['calculated_price'] = price;
                    setState(() {
                      widget.model.sashOverride = mutableSelected;
                      widget.model.updateAllSashThicknesses();
                      widget.model.refreshUI();
                    });
                  },
                ),
              ),
            );
          }
        }

        if (zone.content == ZoneContent.singleSash ||
            zone.content == ZoneContent.doubleSash ||
            zone.content == ZoneContent.slidingSash) {
          children.add(const SizedBox(width: 8));
          final allowedDirections =
          (zone.content == ZoneContent.doubleSash ||
              zone.content == ZoneContent.slidingSash ||
              !widget.model.hasBottomFrame)
              ? [OpenDirection.left, OpenDirection.right]
              : OpenDirection.values;

          children.addAll(
            allowedDirections.map(
                  (dir) =>
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ContentButton(
                      label: _getDirectionName(dir),
                      icon: Icons.open_with_rounded,
                      selected: zone.openDirection == dir,
                      onPressed: () =>
                          widget.model.setSelectedZoneOpenDirection(dir),
                    ),
                  ),
            ),
          );
        }

        if (zone.content == ZoneContent.singleSash ||
            zone.content == ZoneContent.doubleSash) {
          String btnLabel = Localization.translate('المقبض (Poignée)', lang);
          IconData btnIcon = Icons.door_back_door_rounded;
          bool btnSelected = false;

          if (zone.isSash105) {
            // Thick Sash (Door)
            if (zone.lockType == LockType.clef) {
              btnLabel = Localization.translate('مقبض الباب بمفتاح', lang);
              btnIcon = Icons.vpn_key_rounded;
              btnSelected = true;
            } else if (zone.lockType == LockType.condamnation) {
              btnLabel = Localization.translate('مقبض الباب حمام', lang);
              btnIcon = Icons.lock_rounded;
              btnSelected = true;
            } else if (zone.lockType == LockType.rouleau) {
              btnLabel = Localization.translate(
                'مقبض كبير ماريشال 1.25 متر',
                lang,
              );
              btnIcon = Icons.door_back_door_rounded;
              btnSelected = true;
            } else if (zone.lockType == LockType.rouleau2000) {
              btnLabel = Localization.translate(
                'مقبض كبير ماريشال 2 متر',
                lang,
              );
              btnIcon = Icons.door_back_door_rounded;
              btnSelected = true;
            } else if (zone.usePvcHandleOnAlu) {
              btnLabel = Localization.translate('Poignée fenêtre', lang);
              btnIcon = Icons.window_rounded;
              btnSelected = true;
            } else if (zone.useOctoHandle) {
              btnLabel = Localization.translate('مقبض أوكتو', lang);
              btnIcon = Icons.radio_button_checked_rounded;
              btnSelected = true;
            } else {
              // Default is Cremone on door
              btnLabel = Localization.translate('مقبض كريمون', lang);
              btnIcon = Icons.door_back_door_rounded;
              btnSelected = true;
            }
          } else {
            // Thin Sash (Window)
            if (zone.lockType == LockType.point) {
              btnLabel = Localization.translate('قفل نقطة', lang);
              btnIcon = Icons.adjust;
              btnSelected = true;
            } else if (zone.useOctoHandle) {
              btnLabel = Localization.translate('مقبض أوكتو', lang);
              btnIcon = Icons.radio_button_checked_rounded;
              btnSelected = true;
            } else {
              btnLabel = (widget.model.isPVC || zone.usePvcHandleOnAlu)
                  ? Localization.translate('Poignée fenêtre', lang)
                  : Localization.translate('مقبض كريمون', lang);
              btnIcon = Icons.window_rounded;
              btnSelected = true;
            }
          }

          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: btnLabel,
              icon: btnIcon,
              selected: btnSelected,
              onPressed: () {
                setState(() {
                  _activeBottomTab = 5;
                });
              },
            ),
          );
        }
        if (zone.content == ZoneContent.slidingSash) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.useClassicHandle
                  ? Localization.translate('مقبض كلاسيكي (كودي)', lang)
                  : Localization.translate('مقبض منزلق (اندراماتيك)', lang),
              icon: Icons.sync_alt_rounded,
              selected: true,
              onPressed: () {
                setState(() {
                  _activeBottomTab = 5;
                });
              },
            ),
          );
        }

        // Sub-zone cell options
        if (widget.model.activeSubZone != null &&
            widget.model.activeSubZone!.contains('cell_') &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash)) {
          final cellKey = widget.model.activeSubZone!;
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.cellIsSash[cellKey] == true
                  ? 'دلفة داخلية (نشطة)'
                  : 'إضافة دلفة داخلية',
              icon: Icons.window,
              selected: zone.cellIsSash[cellKey] == true,
              onPressed: () {
                setState(() {
                  widget.model.toggleSelectedCellSash();
                });
              },
            ),
          );
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.cellIsDoubleSash[cellKey] == true
                  ? 'ضلفتان داخليتان (نشطة)'
                  : 'إضافة ضلفتان داخليتان',
              icon: Icons.window,
              selected: zone.cellIsDoubleSash[cellKey] == true,
              onPressed: () {
                setState(() {
                  widget.model.toggleSelectedCellDoubleSash();
                });
              },
            ),
          );

          if (zone.cellIsSash[cellKey] == true ||
              zone.cellIsDoubleSash[cellKey] == true) {
            children.add(const SizedBox(width: 8));
            // Add 104/105 switch
            children.add(
              Builder(
                builder: (context) {
                  bool isCellSash105 = false;
                  final currentOverride = zone.cellSashOverrides[cellKey];
                  if (currentOverride != null) {
                    final code =
                        currentOverride['code']?.toString().toLowerCase() ?? '';
                    final name =
                        currentOverride['name']?.toString().toLowerCase() ?? '';
                    if (code.contains('104') || name.contains('104')) {
                      isCellSash105 = false;
                    } else if (code.contains('105') ||
                        code.contains('porte') ||
                        code.contains('ouvr') ||
                        name.contains('105') ||
                        name.contains('porte') ||
                        name.contains('ouvr') ||
                        name.contains('بورت')) {
                      isCellSash105 = true;
                    } else {
                      isCellSash105 = false;
                    }
                  } else {
                    isCellSash105 = zone.isSash105;
                  }

                  bool has104105Option = false;
                  if (activeSeriesForSystem != null) {
                    for (var sec in activeSeriesForSystem!.sections) {
                      if (sec.code.contains('104') ||
                          sec.code.contains('105') ||
                          sec.name.contains('104') ||
                          sec.name.contains('105')) {
                        has104105Option = true;
                        break;
                      }
                    }
                  }

                  if (!has104105Option) return const SizedBox.shrink();

                  return _ContentButton(
                    label: isCellSash105
                        ? 'الظلفة 105 (صندوق باب)'
                        : 'الظلفة 104 (نافذة)',
                    icon: Icons.swap_horiz,
                    selected: true,
                    onPressed: () async {
                      await widget.model.toggleCellSashType104105(cellKey);
                      setState(() {});
                    },
                  );
                },
              ),
            );

            // Sub-sash opening direction
            children.add(const SizedBox(width: 8));
            children.add(
              Builder(
                builder: (context) {
                  final isDouble = zone.cellIsDoubleSash[cellKey] == true;
                  final currentDir = () {
                    final currentOverride = zone.cellSashOverrides[cellKey];
                    final defaultDir = isDouble
                        ? OpenDirection.right
                        : OpenDirection.left;
                    if (currentOverride != null &&
                        currentOverride['openDirection'] != null) {
                      final dirStr = currentOverride['openDirection']
                          .toString();
                      return OpenDirection.values.firstWhere(
                            (d) => d.name == dirStr,
                        orElse: () => defaultDir,
                      );
                    }
                    return defaultDir;
                  }();

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...(isDouble
                          ? [OpenDirection.left, OpenDirection.right]
                          : OpenDirection.values)
                          .map(
                            (dir) =>
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: _ContentButton(
                                label: _getDirectionName(dir),
                                icon: Icons.open_with_rounded,
                                selected: currentDir == dir,
                                onPressed: () {
                                  setState(() {
                                    widget.model.setCellSashOpenDirection(
                                      cellKey,
                                      dir,
                                    );
                                  });
                                },
                              ),
                            ),
                      ),
                    ],
                  );
                },
              ),
            );
          }
        }
        if (!widget.model.isPVC &&
            widget.model.systemMode != 'sliding' &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash)) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.hasSashPlintheBottom
                  ? 'حذف بلانت الضلفة'
                  : 'إضافة بلانت للضلفة',
              icon: Icons.border_bottom_rounded,
              selected: zone.hasSashPlintheBottom,
              onPressed: () {
                setState(() {
                  widget.model.toggleSelectedZoneSashPlintheBottom();
                });
              },
            ),
          );
        }
        break;

      case 3: // عامود (Mullion settings)
        if (isMullionSelected) {
          String key =
              "${widget.model.selection.isHorizontalMullion!
              ? 'H'
              : 'V'}_${widget.model.selection.mullionPosition!.toStringAsFixed(
              1)}";
          MullionProfileType currentType =
              widget.model.mullionProfiles[key] ?? MullionProfileType.standard;

          children.add(
            _ContentButton(
              label: 'حذف العامود',
              icon: Icons.delete_forever_rounded,
              selected: false,
              onPressed: () {
                setState(() {
                  widget.model.deleteSelectedMullion();
                });
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: 'Traverse',
              icon: Icons.horizontal_rule_rounded,
              selected: currentType == MullionProfileType.standard,
              onPressed: () {
                setState(() {
                  widget.model.setMullionProfile(MullionProfileType.standard);
                });
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: 'Cadre doublé',
              icon: Icons.splitscreen_rounded,
              selected: currentType == MullionProfileType.flat,
              onPressed: () {
                setState(() {
                  widget.model.setMullionProfile(MullionProfileType.flat);
                });
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: 'Cadre 140',
              icon: Icons.view_headline_rounded,
              selected: currentType == MullionProfileType.grooved,
              onPressed: () {
                setState(() {
                  widget.model.setMullionProfile(MullionProfileType.grooved);
                });
              },
            ),
          );
        } else {
          children.add(
            const Text(
              'الرجاء تحديد عامود من الرسم بالضغط عليه لتعديله',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        }
        break;

      case 4: // زجاج / حشوات (Glass settings)
        final GlassSpecification spec = zone != null
            ? (widget.model.activeSubZone != null
            ? zone.getGlassForCell(widget.model.activeSubZone)
            : zone.glass)
            : const GlassSpecification();

        final bool isSliding =
            widget.systemMode == 'sliding' ||
                (widget.systemMode == 'mixed' &&
                    zone != null &&
                    zone.content == ZoneContent.slidingSash);
        if (!isSliding) {
          final parcloseOverride =
          widget.model.componentOverrides['باكيت الزجاج (Parclose)'];
          final parcloseLabel = parcloseOverride != null
              ? '${Localization.translate('Parclose',
              lang)}: ${parcloseOverride['code']} (${(parcloseOverride['max_glass_thickness'] as num?)
              ?.toDouble() ?? 0.0} ${Localization.translate('مم', lang)})'
              : Localization.translate('Choisir la parclose', lang);
          children.add(
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ContentButton(
                label: parcloseLabel,
                icon: Icons.border_outer_rounded,
                selected: parcloseOverride != null,
                onPressed: () => _showParcloseSelectorDialog(context),
              ),
            ),
          );
          children.add(const SizedBox(width: 12));
        }

        String getGlassDescription(GlassSpecification spec, AppLanguage lang) {
          String structName = '';
          switch (spec.structure) {
            case GlassStructure.simple:
              structName = Localization.translate('عادي', lang);
              break;
            case GlassStructure.double:
              structName = Localization.translate('مزدوج', lang);
              break;
            case GlassStructure.closed:
              structName = Localization.translate('بانو', lang);
              break;
          }

          if (spec.structure == GlassStructure.double) {
            final double tOuter = spec.thicknessOuter ?? 4.0;
            final int intercall = spec.intercallThickness;
            final double tInner = spec.thicknessInner ?? 4.0;
            structName += ' (${tOuter.toInt()}-${intercall}-${tInner.toInt()})';
          }

          String finishName = '';
          if (spec.structure == GlassStructure.closed) {
            finishName = Localization.translate(
              widget.model.getClosedColoreName(spec.colorP),
              lang,
            );
          } else {
            finishName = Localization.translate(
              widget.model.getFinishName(spec.finishOuter),
              lang,
            );
            if (spec.finishOuter == GlassFinish.stopSol) {
              final String colName = Localization.translate(
                widget.model.getArabicColorName(spec.colorOuter),
                lang,
              );
              finishName += ' ($colName)';
            }
          }
          if (finishName.isNotEmpty) {
            structName += ' - $finishName';
          }
          return structName;
        }

        final isDark = Theme
            .of(context)
            .brightness == Brightness.dark;
        final String glassDesc = getGlassDescription(spec, lang);

        children.add(
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E2C)
                    : Colors.blue.shade50.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.blue.shade800 : Colors.blue.shade100,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${Localization.translate(
                        'الزجاج الحالي', lang)}: $glassDesc',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.blue.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        children.add(const SizedBox(width: 12));
        children.add(
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ContentButton(
              label: Localization.translate('تخصيص مظهر الزجاج', lang),
              icon: Icons.edit_note_rounded,
              selected: true,
              onPressed: () {
                setState(() {
                  _isLeftDrawerOpen = true;
                });
              },
            ),
          ),
        );

        break;

      case 5: // مقابض (Handles/Locks settings)
        if (zone.content != ZoneContent.singleSash &&
            zone.content != ZoneContent.doubleSash &&
            zone.content != ZoneContent.slidingSash) {
          children.add(
            Text(
              Localization.translate(
                'الرجاء تحديد ضلفة من الرسم لتعديل مقابضها',
                lang,
              ),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        } else {
          // The selected profile is the source of truth.  A thick profile can
          // be selected inside a divided double sash before the old zone flag
          // is refreshed, so checking only `zone.isSash105` hid all door
          // handle buttons and left only the optional two-handle button.
          final isDoorSash = widget.model.selectedZoneUsesSash105;
          if (zone.content == ZoneContent.slidingSash) {
            if (!widget.model.isPVC) {
              // 1. Entrematique handle
              children.add(
                _ContentButton(
                  label: Localization.translate(
                    'مقبض منزلق (اندراماتيك)',
                    lang,
                  ),
                  icon: Icons.sync_alt_rounded,
                  selected: zone.useClassicHandle != true,
                  onPressed: () {
                    setState(() {
                      widget.model.setSelectedZoneHandle();
                    });
                  },
                ),
              );
              children.add(const SizedBox(width: 8));

              // 2. Classic handle
              children.add(
                _ContentButton(
                  label: Localization.translate(
                    'مقبض كلاسيكي (بواني كودي)',
                    lang,
                  ),
                  icon: Icons.sync_alt_rounded,
                  selected: zone.useClassicHandle == true,
                  onPressed: () {
                    setState(() {
                      widget.model.setSelectedZoneHandle(
                        useClassicHandle: true,
                      );
                    });
                  },
                ),
              );
            } else {
              children.add(
                Text(
                  Localization.translate(
                    'لا توجد خيارات مقابض إضافية للمنزلق PVC',
                    lang,
                  ),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              );
            }
          } else if (widget.model.isPVC) {
            if (isDoorSash) {
              // PVC Door sashes
              // 1. Key handle. A shutter does not remove door-handle choices.
              if (zone.content != ZoneContent.slidingSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض الباب بمفتاح', lang),
                    icon: Icons.vpn_key_rounded,
                    selected: zone.lockType == LockType.clef,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.clef,
                        );
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 2. Bathroom handle. A shutter does not remove door-handle choices.
              if (zone.content != ZoneContent.slidingSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض الباب حمام', lang),
                    icon: Icons.lock_rounded,
                    selected: zone.lockType == LockType.condamnation,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.condamnation,
                        );
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 3. A thick sash can also use the ordinary window handle.
              children.add(
                _ContentButton(
                  label: Localization.translate('Poignée fenêtre', lang),
                  icon: Icons.window_rounded,
                  selected:
                  zone.lockType == LockType.none &&
                      zone.useOctoHandle != true &&
                      zone.usePvcHandleOnAlu == true,
                  onPressed: () {
                    setState(() {
                      widget.model.setSelectedZoneHandle(
                        usePvcHandleOnAlu: true,
                      );
                    });
                  },
                ),
              );
              children.add(const SizedBox(width: 8));

              // 4. Maréchal handle (if no bottom frame AND no roller shutter)
              if (widget.model.hasBottomFrame == false &&
                  widget.model.hasShutter == false) {
                final double doorHeight = zone.boundary.height;
                if (doorHeight >= 1250.0) {
                  children.add(
                    _ContentButton(
                      label: Localization.translate(
                        'مقبض كبير ماريشال 1.25 متر',
                        lang,
                      ),
                      icon: Icons.door_back_door_rounded,
                      selected: zone.lockType == LockType.rouleau,
                      onPressed: () {
                        setState(() {
                          widget.model.setSelectedZoneHandle(
                            lockType: LockType.rouleau,
                          );
                        });
                      },
                    ),
                  );
                  children.add(const SizedBox(width: 8));

                  if (doorHeight > 2000.0) {
                    children.add(
                      _ContentButton(
                        label: Localization.translate(
                          'مقبض كبير ماريشال 2 متر',
                          lang,
                        ),
                        icon: Icons.door_back_door_rounded,
                        selected: zone.lockType == LockType.rouleau2000,
                        onPressed: () {
                          setState(() {
                            widget.model.setSelectedZoneHandle(
                              lockType: LockType.rouleau2000,
                            );
                          });
                        },
                      ),
                    );
                  }
                }
              }
            } else {
              // PVC Window sashes
              if (zone.content == ZoneContent.doubleSash) {
                // Double sash PVC window: only window handle (x2)
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض نافذة', lang),
                    icon: Icons.door_back_door_rounded,
                    selected:
                    zone.lockType == LockType.none &&
                        zone.useOctoHandle != true,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle();
                      });
                    },
                  ),
                );
              } else {
                // Single sash PVC window: window handle, and Octo handle
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض نافذة', lang),
                    icon: Icons.door_back_door_rounded,
                    selected:
                    zone.lockType == LockType.none &&
                        zone.useOctoHandle != true,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle();
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));

                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض أوكتو', lang),
                    icon: Icons.radio_button_checked_rounded,
                    selected:
                    zone.lockType == LockType.none &&
                        zone.useOctoHandle == true,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle(useOctoHandle: true);
                      });
                    },
                  ),
                );
              }
            }
          } else {
            // Aluminium Swing Sashes
            if (isDoorSash) {
              // Door sashes (Thick Sash / الظلفة الغليظة)

              // 1. Cremone handle (مقبض كريمون)
              children.add(
                _ContentButton(
                  label: zone.content == ZoneContent.doubleSash
                      ? Localization.translate('مقبض كريمون', lang)
                      : Localization.translate('مقبض كريمون', lang),
                  icon: Icons.door_back_door_rounded,
                  selected:
                  zone.lockType == LockType.none &&
                      zone.useOctoHandle != true &&
                      zone.usePvcHandleOnAlu != true,
                  onPressed: () {
                    setState(() {
                      widget.model.setSelectedZoneHandle();
                    });
                  },
                ),
              );
              children.add(const SizedBox(width: 8));

              // 2. Key handle (مقبض الباب بمفتاح), including shutter windows.
              if (zone.content != ZoneContent.slidingSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض الباب بمفتاح', lang),
                    icon: Icons.vpn_key_rounded,
                    selected: zone.lockType == LockType.clef,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.clef,
                        );
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 3. Bathroom handle (مقبض الباب حمام), including shutter windows.
              if (zone.content != ZoneContent.slidingSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض الباب حمام', lang),
                    icon: Icons.lock_rounded,
                    selected: zone.lockType == LockType.condamnation,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.condamnation,
                        );
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 4. Octo handle (مقبض أوكتو - single-sash only)
              if (zone.content == ZoneContent.singleSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض أوكتو', lang),
                    icon: Icons.radio_button_checked_rounded,
                    selected:
                    zone.lockType == LockType.none &&
                        zone.useOctoHandle == true,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle(useOctoHandle: true);
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 5. Maréchal handle (if no bottom frame AND no roller shutter)
              if (widget.model.hasBottomFrame == false &&
                  widget.model.hasShutter == false) {
                final double doorHeight = zone.boundary.height;
                if (doorHeight >= 1250.0) {
                  children.add(
                    _ContentButton(
                      label: Localization.translate(
                        'مقبض كبير ماريشال 1.25 متر',
                        lang,
                      ),
                      icon: Icons.door_back_door_rounded,
                      selected: zone.lockType == LockType.rouleau,
                      onPressed: () {
                        setState(() {
                          widget.model.setSelectedZoneHandle(
                            lockType: LockType.rouleau,
                          );
                        });
                      },
                    ),
                  );
                  children.add(const SizedBox(width: 8));

                  if (doorHeight > 2000.0) {
                    children.add(
                      _ContentButton(
                        label: Localization.translate(
                          'مقبض كبير ماريشال 2 متر',
                          lang,
                        ),
                        icon: Icons.door_back_door_rounded,
                        selected: zone.lockType == LockType.rouleau2000,
                        onPressed: () {
                          setState(() {
                            widget.model.setSelectedZoneHandle(
                              lockType: LockType.rouleau2000,
                            );
                          });
                        },
                      ),
                    );
                    children.add(const SizedBox(width: 8));
                  }
                }
              }

              // Window handle (Poignée fenêtre)
              children.add(
                _ContentButton(
                  label: zone.content == ZoneContent.doubleSash
                      ? Localization.translate('Poignée fenêtre', lang)
                      : Localization.translate('Poignée fenêtre', lang),
                  icon: Icons.window_rounded,
                  selected:
                  zone.lockType == LockType.none &&
                      zone.useOctoHandle != true &&
                      zone.usePvcHandleOnAlu == true,
                  onPressed: () {
                    setState(() {
                      widget.model.setSelectedZoneHandle(
                        usePvcHandleOnAlu: true,
                      );
                    });
                  },
                ),
              );
            } else {
              // Window sashes (Thin Sash / الظلفة الرقيقة)
              // Window handle (Poignée fenêtre)
              children.add(
                _ContentButton(
                  label: zone.content == ZoneContent.doubleSash
                      ? Localization.translate('Poignée fenêtre', lang)
                      : Localization.translate('Poignée fenêtre', lang),
                  icon: Icons.window_rounded,
                  selected:
                  zone.lockType == LockType.none &&
                      zone.useOctoHandle != true &&
                      zone.usePvcHandleOnAlu == true,
                  onPressed: () {
                    setState(() {
                      widget.model.setSelectedZoneHandle(
                        usePvcHandleOnAlu: true,
                      );
                    });
                  },
                ),
              );
              children.add(const SizedBox(width: 8));

              if (zone.content == ZoneContent.doubleSash) {
                // Cremone x2
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض كريمون', lang),
                    icon: Icons.door_back_door_rounded,
                    selected:
                    zone.lockType == LockType.none &&
                        zone.useOctoHandle != true &&
                        zone.usePvcHandleOnAlu != true,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle();
                      });
                    },
                  ),
                );
              } else {
                // Single sash: Cremone, Octo, Point Lock
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض كريمون', lang),
                    icon: Icons.door_back_door_rounded,
                    selected:
                    zone.lockType == LockType.none &&
                        zone.useOctoHandle != true &&
                        zone.usePvcHandleOnAlu != true,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle();
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));

                // Octo
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض أوكتو', lang),
                    icon: Icons.radio_button_checked_rounded,
                    selected:
                    zone.lockType == LockType.none &&
                        zone.useOctoHandle == true &&
                        zone.usePvcHandleOnAlu != true,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle(useOctoHandle: true);
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));

                // Point Lock
                children.add(
                  _ContentButton(
                    label: Localization.translate('قفل نقطة', lang),
                    icon: Icons.adjust,
                    selected: zone.lockType == LockType.point,
                    onPressed: () {
                      setState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.point,
                        );
                      });
                    },
                  ),
                );
              }
            }
          }
        }
        if (zone.content == ZoneContent.doubleSash) {
          children.add(const SizedBox(width: 8));
          final twoHandlesLabel = switch (lang) {
            AppLanguage.arabic => 'إضافة مقبضين',
            AppLanguage.french => 'Ajouter deux poignées',
            AppLanguage.english => 'Add two handles',
          };
          children.add(
            _ContentButton(
              label: twoHandlesLabel,
              icon: Icons.pan_tool_alt_rounded,
              selected: zone.doubleSashHasTwoHandles,
              onPressed: () {
                setState(() {
                  widget.model.setSelectedZoneDoubleHandles(
                    !zone.doubleSashHasTwoHandles,
                  );
                });
              },
            ),
          );
        }
        break;
    }

    return children;
  }

  Widget _buildCollapsedStatusBar(BuildContext context) {
    final zone = widget.model.selectedZone;
    final lang = Provider
        .of<AppSettingsProvider>(context)
        .language;

    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  zone == null
                      ? Localization.translate(
                    'انقر لتحديد وتعديل أي منطقة',
                    lang,
                  )
                      : '${Localization.translate(
                      'المنطقة المحددة', lang)}: ${Localization.translate(
                      zone.content.name, lang)}  |  ${Localization.translate(
                      'الأبعاد', lang)}: ${zone.boundary.width.toInt()} × ${zone
                      .boundary.height.toInt()} mm',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? Colors.green.shade700
                                : Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            if (widget.model.zones.every(
                                  (z) => z.content == ZoneContent.empty,
                            )) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    Localization.translate(
                                      'الرجاء رسم أو إضافة جزء في النافذة أولاً قبل حساب التكلفة!',
                                      lang,
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            // The frame picked in the drawing is the source
                            // of truth. Do not replace it merely because side
                            // covers are enabled: a standalone cover is valid
                            // with a non-integrated frame.
                            final activeFrame = widget.model
                                .activeFrameOverride;
                            if (activeFrame != null &&
                                widget.model.selectedDbColor != null) {
                              int cId = widget.model.selectedDbColor!['id'];
                              final rawFrameId = activeFrame['id'];
                              final sId = rawFrameId is num
                                  ? rawFrameId.toInt()
                                  : int.tryParse(rawFrameId?.toString() ?? '');
                              if (sId == null) return;
                              final db = SqlDatabase();
                              double updatedPrice = await db.getSectionPrice(
                                sId,
                                cId,
                              );
                              activeFrame['calculated_price'] = updatedPrice;
                            }
                            if (!context.mounted) return;
                            widget.model.clearSelection();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    MaterialConsumptionScreen(
                                      model: widget.model,
                                    ),
                              ),
                            ).then((res) {
                              if (res != null) {
                                if (context.mounted) {
                                  Navigator.pop(context, widget.model);
                                }
                              }
                            });
                          },
                          child: Text(
                            Localization.translate('الالكمية والتكلفة', lang),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showParcloseSelectorDialog(BuildContext context) async {
    final dbInstance = SqlDatabase();
    final d = await dbInstance.db;
    if (d == null || activeSeriesForSystem == null) return;

    final List<Map<String, dynamic>> res = await d.query(
      'Sections',
      where: 'series_id = ? AND (type = ? OR type LIKE ? OR name LIKE ?)',
      whereArgs: [
        activeSeriesForSystem!.id,
        'parclose',
        '%parclose%',
        '%باكيت%',
      ],
    );

    // A double glazing pack must only be paired with a parclose that leaves
    // room for a real Intercall. Filter invalid single/small parcloses from
    // this selector so they cannot be chosen after the automatic selection.
    var doublePaneThickness = 0.0;
    void considerGlass(GlassSpecification glass) {
      if (glass.structure != GlassStructure.double) return;
      final panes = (glass.thicknessOuter ?? 4.0) +
          (glass.thicknessInner ?? 4.0);
      if (panes > doublePaneThickness) doublePaneThickness = panes;
    }

    for (final zone in widget.model.zones) {
      considerGlass(zone.glass);
      for (final glass in zone.cellGlassSpec.values) {
        considerGlass(glass);
      }
    }
    final availableParcloses = doublePaneThickness > 0
        ? res.where((item) {
      final raw = item['max_glass_thickness'];
      final capacity = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '');
      return (capacity ?? 0) >
          (doublePaneThickness > 10.0 ? doublePaneThickness : 10.0);
    }).toList()
        : res;

    if (!context.mounted) return;

    final lang = Provider
        .of<AppSettingsProvider>(
      context,
      listen: false,
    )
        .language;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(Localization.translate('Choisir la parclose', lang)),
          content: availableParcloses.isEmpty
              ? Text(
            Localization.translate(
              'لا توجد عناصر باكيت زجاج مسجلة لهذه السلسلة في قاعدة البيانات',
              lang,
            ),
          )
              : SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableParcloses.length,
              itemBuilder: (context, index) {
                final item = availableParcloses[index];
                final double maxThickness =
                    (item['max_glass_thickness'] as num?)?.toDouble() ??
                        0.0;
                return ListTile(
                  title: Text('${item['code']} - ${item['name']}'),
                  subtitle: Text(
                    '${Localization.translate('السمك الأقصى للزجاج',
                        lang)}: $maxThickness ${Localization.translate(
                        'مم', lang)}',
                  ),
                  trailing: Icon(
                    widget.model
                        .componentOverrides['باكيت الزجاج (Parclose)']?['id'] ==
                        item['id']
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: Colors.green,
                  ),
                  onTap: () async {
                    final mutableItem = Map<String, dynamic>.from(item);
                    final colorId = widget.model.selectedDbColor?['id'];
                    final double price = await dbInstance.getSectionPrice(
                      item['id'] as int,
                      colorId,
                    );
                    mutableItem['calculated_price'] = price;

                    setState(() {
                      widget
                          .model
                          .componentOverrides['باكيت الزجاج (Parclose)'] =
                          mutableItem;
                    });
                    widget
                        .model
                        .fitDoubleGlassIntercallsToSelectedParclose();
                    await widget.model.updateGlassGasket();
                    widget.model.refreshUI();
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
          ],
        );
      },
    );
  }
}

/// A horizontal scroll area that works with touch, mouse dragging, trackpads,
/// and the vertical mouse wheel on desktop.  Flutter normally sends the wheel
/// to the nearest vertical scroll view, which made hidden drawer options
/// (such as Manivelle and Moteur) unreachable on Windows.
class _HorizontalWheelScrollArea extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  const _HorizontalWheelScrollArea({required this.builder});

  @override
  State<_HorizontalWheelScrollArea> createState() =>
      _HorizontalWheelScrollAreaState();
}

class _HorizontalWheelScrollAreaState
    extends State<_HorizontalWheelScrollArea> {
  final ScrollController _controller = ScrollController();

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;

    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;

    final position = _controller.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < 0.5) return;

    // Claim the wheel signal so an enclosing vertical ListView does not
    // consume it before this horizontal row can move.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (_controller.hasClients) _controller.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: true,
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.unknown,
        },
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: _handlePointerSignal,
        child: Scrollbar(
          controller: _controller,
          interactive: true,
          thumbVisibility:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
          child: widget.builder(context, _controller),
        ),
      ),
    );
  }
}

class _IntercallButton extends StatelessWidget {
  final int thickness;
  final bool selected;
  final VoidCallback onPressed;
  final bool showWarning;

  const _IntercallButton({
    required this.thickness,
    required this.selected,
    required this.onPressed,
    this.showWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
              ? Colors.blue.shade900.withValues(alpha: 0.3)
              : Colors.blue.shade50)
              : (isDark ? const Color(0xFF2E2E3E) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.blue
                : (isDark ? Colors.white24 : Colors.grey.shade300),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Intercall',
              style: TextStyle(
                color: isDark
                    ? Colors.white
                    : (selected ? Colors.blue.shade900 : Colors.grey.shade800),
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 5),
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.crop_free_rounded,
                  size: 22,
                  color: isDark
                      ? Colors.white
                      : (selected ? Colors.blue : Colors.grey.shade500),
                ),
                Text(
                  thickness.toString(),
                  style: TextStyle(
                    color: isDark
                        ? Colors.white
                        : (selected ? Colors.blue.shade700 : Colors.black87),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 5),
            Text(
              'مم',
              style: TextStyle(
                color: isDark
                    ? Colors.white
                    : (selected ? Colors.blue.shade900 : Colors.grey.shade800),
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (showWarning) ...[
              const SizedBox(width: 5),
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final Color color;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    final disabledBg = isDark ? const Color(0xFF2E2E3E) : Colors.grey.shade200;
    final disabledFg = isDark ? Colors.white38 : Colors.grey;
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 16, color: enabled ? Colors.white : disabledFg),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: enabled ? Colors.white : disabledFg,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? color : disabledBg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        elevation: 0,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// زر خيار الستار - Chip Style
// ─────────────────────────────────────────────────────────────────────────────
class _ShutterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ShutterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.grey.shade100,
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? color : Colors.grey.shade600,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? color : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final bool showWarning;

  const _ContentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.showWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
              ? Colors.blue.shade900.withValues(alpha: 0.3)
              : Colors.blue.shade50)
              : (isDark ? const Color(0xFF2E2E3E) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.blue
                : (isDark ? Colors.white24 : Colors.grey.shade300),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isDark
                  ? Colors.white
                  : (selected ? Colors.blue : Colors.grey.shade600),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isDark
                    ? Colors.white
                    : (selected ? Colors.blue.shade900 : Colors.grey.shade800),
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (showWarning) ...[
              const SizedBox(width: 5),
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppWorkspacePainter extends CustomPainter {
  final WindowModel model;
  final double userScale;
  final Offset userPan;

  AppWorkspacePainter({
    required this.model,
    this.userScale = 1.0,
    this.userPan = Offset.zero,
  }) : super(repaint: model);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(model.canvasDx + userPan.dx, model.canvasDy + userPan.dy);
    canvas.scale(model.canvasScale * userScale);

    if (model.width > 0 && model.height > 0 && model.zones.isNotEmpty) {
      final painter = WindowPainter(
        model: model,
        showDrawingDimensions: true,
      );
      painter.paint(canvas, size);
      // Keep the exterior dimensions: they are the main total dimensions of
      // the frame. The labels below only add compact dimensions inside each
      // visible profile.
      _paintDimensions(canvas, model, Offset.zero);
      _paintDrawingProfileDimensions(canvas, model);

      final selectedFrameId =
          model.selection.type == SelectionType.frame
          ? model.selection.zoneId
          : null;
      if (model.isDrawingMode && selectedFrameId != null) {
        WindowZone? selectedFrame;
        for (final zone in model.zones) {
          if (zone.id == selectedFrameId) {
            selectedFrame = zone;
            break;
          }
        }
        if (selectedFrame != null) {
          final thickness = model.profileThickness;
          final frameRect = Rect.fromLTRB(
            selectedFrame.boundary.left - thickness,
            selectedFrame.boundary.top - thickness,
            selectedFrame.boundary.right + thickness,
            selectedFrame.boundary.bottom + thickness,
          );
          final side = 18.0 / (model.canvasScale * userScale);
          final outline = Paint()
            ..color = Colors.blue.shade700
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0 / (model.canvasScale * userScale);
          final fill = Paint()
            ..color = Colors.blue.shade600
            ..style = PaintingStyle.fill;
          final border = Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / (model.canvasScale * userScale);

          canvas.drawRect(frameRect, outline);
          final handles = <Offset>[
            frameRect.topLeft,
            Offset(frameRect.center.dx, frameRect.top),
            frameRect.topRight,
            Offset(frameRect.right, frameRect.center.dy),
            frameRect.bottomRight,
            Offset(frameRect.center.dx, frameRect.bottom),
            frameRect.bottomLeft,
            Offset(frameRect.left, frameRect.center.dy),
          ];
          for (final center in handles) {
            final rect = Rect.fromCenter(
              center: center,
              width: side,
              height: side,
            );
            canvas.drawRect(rect, fill);
            canvas.drawRect(rect, border);
          }
        }
      }

      if (model.isDrawingMode &&
          model.canBeArchedOrSlanted &&
          model.selection.type == SelectionType.frame &&
          model.selection.zoneId == null) {
        final double side = 18.0 / (model.canvasScale * userScale);
        final fillPaint = Paint()
          ..color = Colors.orangeAccent
          ..style = PaintingStyle.fill;
        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / (model.canvasScale * userScale);
        final shadowPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;

        void drawHandle(Offset center) {
          final rect = Rect.fromCenter(
            center: center,
            width: side,
            height: side,
          );
          final shadowRect = Rect.fromCenter(
            center: center + Offset(0, 1.5 / (model.canvasScale * userScale)),
            width: side,
            height: side,
          );
          canvas.drawRect(shadowRect, shadowPaint);
          canvas.drawRect(rect, fillPaint);
          canvas.drawRect(rect, borderPaint);
        }

        drawHandle(Offset(0, model.topSlantLeftY));
        drawHandle(Offset(model.width, model.topSlantRightY));
        drawHandle(
          Offset(
            model.width / 2,
            math.min(model.topSlantLeftY, model.topSlantRightY) -
                (model.archHeight * 2),
          ),
        );
      }
    }

    if ((model.zones.isEmpty || model.drawingMode == 'add_frame') &&
        model.isDrawingMode &&
        model.drawingStart != null &&
        model.drawingCurrent != null) {
      final r = Rect.fromPoints(model.drawingStart!, model.drawingCurrent!);
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.blueAccent.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0 / (model.canvasScale * userScale),
      );
    }
    canvas.restore();
  }

  /// Draws the technical dimensions inside the corresponding physical
  /// profile. These labels exist only in the interactive drawing editor; the
  /// normal painter is also used by customer previews and PDF documents.
  void _paintDrawingProfileDimensions(Canvas canvas, WindowModel model) {
    final frameThickness = model.profileThickness;
    if (frameThickness <= 0) return;

    final frameRects = model.getFrameRects();
    final frameSection = model.getSectionByType('frame');
    double numberFrom(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    String codeFrom(Map<String, dynamic>? override, AluminumSection? section) {
      final overridden = (override?['code'] ?? '').toString().trim();
      return overridden.isNotEmpty ? overridden : (section?.code ?? '').trim();
    }

    String cutLabel(double value, String code) {
      final rounded = (math.max(0.0, value) * 10).round() / 10;
      final size = (rounded - rounded.round()).abs() < 0.001
          ? rounded.round().toString()
          : rounded.toStringAsFixed(1);
      return code.isEmpty ? size : '$size ($code)';
    }

    final activeFrame = model.activeFrameOverride;
    var integratedCoverWidth =
        numberFrom(activeFrame?['couvre_joint_width']);
    if (integratedCoverWidth <= 0) {
      integratedCoverWidth = frameSection?.couvreJointWidth ?? 0.0;
    }
    final hasIntegratedCover =
        model.isIntegratedFrame &&
            model.isSideCoverAllowed &&
            integratedCoverWidth > 0;
    final hasSeparateCover =
        !hasIntegratedCover &&
        model.hasSideCovers &&
        model.isSideCoverAllowed;
    final separateCover = model.selectedSideCover;
    final separateCoverWidth = model.sideCoverWidth;
    final separateCoverThickness = numberFrom(
      model.sideCoverOverride?['couvre_joint_thickness'] ??
          separateCover?.couvreJointThickness,
    );
    final frameCode = codeFrom(activeFrame, frameSection);
    final separateCoverCode = codeFrom(
      model.sideCoverOverride,
      separateCover,
    );
    final weldAllowance = model.isFramePVC ? 5.0 : 0.0;

    // The labels inside profiles are cutting dimensions. Total exterior
    // dimensions remain outside the drawing and are deliberately untouched.
    // An integrated cover is part of the frame profile, so its cut is shown
    // only on the cover band—not a second time on the frame itself.
    if (!hasIntegratedCover) {
      for (final frame in frameRects) {
        final isOnlyFrame = frameRects.length == 1;
        final netHeight = model.hasShutter && !model.isCaissonTunnel
            ? model.height - model.shutterBoxHeight
            : model.height;
        final frameWidth = hasSeparateCover
            ? frame.width - (2 * separateCoverThickness) + weldAllowance
            : (isOnlyFrame ? model.width : frame.width) + weldAllowance;
        final frameHeight = hasSeparateCover
            ? frame.height - (2 * separateCoverThickness) + weldAllowance
            : (isOnlyFrame ? netHeight : frame.height) + weldAllowance;
        _paintProfileDimensionLabel(
          canvas,
          cutLabel(frameWidth, frameCode),
          Rect.fromLTWH(
            frame.left + 2,
            frame.top + 1,
            math.max(0.0, frame.width - 4),
            math.max(0.0, frameThickness - 2),
          ),
        );
        _paintProfileDimensionLabel(
          canvas,
          cutLabel(frameHeight, frameCode),
          Rect.fromLTWH(
            frame.left + 1,
            frame.top + 2,
            math.max(0.0, frameThickness - 2),
            math.max(0.0, frame.height - 4),
          ),
          vertical: true,
        );
      }
    }

    if (hasIntegratedCover || hasSeparateCover) {
      final coverWidth = hasIntegratedCover
          ? integratedCoverWidth
          : separateCoverWidth;
      final coverCode = hasIntegratedCover ? frameCode : separateCoverCode;
      final coverWeldAllowance = hasSeparateCover && model.isFramePVC ? 5.0 : 0.0;
      final coverCutWidth = hasIntegratedCover
          ? model.width + (2 * coverWidth) + weldAllowance
          : model.width + (2 * coverWidth) + coverWeldAllowance;
      final coverCutHeight = hasIntegratedCover
          ? model.height + (2 * coverWidth) + weldAllowance
          : model.height + (2 * coverWidth) + coverWeldAllowance;
      if (coverWidth > 0) {
      final isInternal = model.isInternalView;
      final hasLeft = isInternal
          ? !model.removedShutterSides.contains('left')
          : !model.removedShutterSides.contains('right');
      final hasTop = !model.removedShutterSides.contains('top');
      if (hasTop) {
        _paintProfileDimensionLabel(
          canvas,
          cutLabel(coverCutWidth, coverCode),
          Rect.fromLTWH(
            2,
            -coverWidth + 1,
            math.max(0.0, model.width - 4),
            math.max(0.0, coverWidth - 2),
          ),
        );
      }
      if (hasLeft) {
        _paintProfileDimensionLabel(
          canvas,
          cutLabel(coverCutHeight, coverCode),
          Rect.fromLTWH(
            -coverWidth + 1,
            2,
            math.max(0.0, coverWidth - 2),
            math.max(0.0, model.height - 4),
          ),
          vertical: true,
        );
      }
      }
    }

    if (model.hasShutter && model.shutterBoxHeight > 0) {
      final boxHeight = model.shutterBoxHeight;
      final boxTop = model.isCaissonTunnel ? -boxHeight : 0.0;
      final boxOverride = model.componentOverrides['الصندوق (Caisson)'];
      final boxCode = (boxOverride?['code'] ?? '').toString().trim();
      // The box label is its cutting length. Its nominal height is already
      // shown by the exterior dimension line at the side of the drawing.
      _paintProfileDimensionLabel(
        canvas,
        cutLabel(model.width - 10.0, boxCode),
        Rect.fromLTWH(
          3,
          boxTop + 4,
          math.max(0.0, model.width - 6),
          math.max(0.0, boxHeight - 8),
        ),
        alignStart: true,
      );
    }
  }

  void _paintProfileDimensionLabel(Canvas canvas,
      String text,
      Rect bounds, {
        bool vertical = false,
        bool alignStart = false,
      }) {
    final crossAxis = vertical ? bounds.width : bounds.height;
    final mainAxis = vertical ? bounds.height : bounds.width;
    if (crossAxis < 12 || mainAxis < 35) return;

    double fontSize = math.min(26.0, math.max(12.0, crossAxis * 0.64));
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFF1565C0),
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(color: Color(0x99FFFFFF), blurRadius: 1)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )
        ..layout();
      if (painter.width <= mainAxis - 8 || fontSize <= 8) break;
      fontSize -= 1.0;
    }
    if (painter.width > mainAxis - 4) return;

    canvas.save();
    if (vertical) {
      final center = Offset(bounds.center.dx, bounds.center.dy);
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-math.pi / 2);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    } else {
      final x = alignStart
          ? bounds.left + 5
          : bounds.center.dx - painter.width / 2;
      final y = bounds.center.dy - painter.height / 2;
      painter.paint(canvas, Offset(x, y));
    }
    canvas.restore();
  }

  void _paintDimensions(Canvas canvas, WindowModel model, Offset pos) {
    final double scW = model.sideCoverWidth;
    double offsetDistTop = 60.0;
    if (model.hasShutter) {
      offsetDistTop += 20.0;
    }
    if (model.hasSideCovers && !model.removedShutterSides.contains('top')) {
      offsetDistTop += scW + 15.0;
    }
    double offsetDistLeft = 50.0;
    if (model.hasSideCovers && !model.removedShutterSides.contains('left')) {
      offsetDistLeft += scW + 15.0;
    }

    final bool isSlantedOrArched =
        model.archHeight > 0 ||
            model.topSlantLeftY != 0 ||
            model.topSlantRightY != 0 ||
            model.bottomSlantLeftY != 0 ||
            model.bottomSlantRightY != 0;

    double widthY;
    if (isSlantedOrArched) {
      double offsetDistBottom = 50.0;
      if (model.hasSideCovers &&
          model.hasBottomFrame &&
          !model.removedShutterSides.contains('bottom')) {
        offsetDistBottom += scW + 15.0;
      }
      double maxBottomY = math.max(
        model.bottomSlantLeftY,
        model.bottomSlantRightY,
      );
      widthY = pos.dy + model.height + maxBottomY + offsetDistBottom;
    } else {
      widthY = pos.dy - offsetDistTop;
      if (model.hasShutter && model.isCaissonTunnel) {
        widthY -= model.shutterBoxHeight;
      }
    }

    _drawDimension(
      canvas,
      '${model.width.toInt()} mm',
      Offset(pos.dx, widthY),
      Offset(pos.dx + model.width, widthY),
      isVerticalLine: false,
    );

    // --- Layer 1: individual frame widths (coupled windows) ---
    if (model.zones.length > 1) {
      final vJoints = model.getVerticalFrameJoints();
      if (vJoints.isNotEmpty) {
        final xCoords = [0.0, ...vJoints, model.width];
        double layer1Y = widthY + 50.0;
        for (int i = 0; i < xCoords.length - 1; i++) {
          double x0 = xCoords[i];
          double x1 = xCoords[i + 1];
          double segW = x1 - x0;
          _drawDimension(
            canvas,
            '${segW.toInt()} mm',
            Offset(pos.dx + x0, layer1Y),
            Offset(pos.dx + x1, layer1Y),
            isVerticalLine: false,
            isSmall: true,
          );
        }
      }
      final hJoints = model.getHorizontalFrameJoints();
      if (hJoints.isNotEmpty) {
        final yCoords = [0.0, ...hJoints, model.height];
        double offsetDistRight = 50.0;
        if (model.hasSideCovers &&
            !model.removedShutterSides.contains('right')) {
          offsetDistRight += scW + 15.0;
        }
        double layer1X = pos.dx + model.width + offsetDistRight + 50.0;
        for (int j = 0; j < yCoords.length - 1; j++) {
          double y0 = yCoords[j];
          double y1 = yCoords[j + 1];
          double segH = y1 - y0;
          _drawDimension(
            canvas,
            '${segH.toInt()} mm',
            Offset(layer1X, pos.dy + y0),
            Offset(layer1X, pos.dy + y1),
            isVerticalLine: true,
            isSmall: true,
          );
        }
      }
    }
    // --- end Layer 1 ---

    if (model.hasShutter) {
      double boxSize = model.shutterBoxHeight;
      if (model.isCaissonTunnel) {
        _drawDimension(
          canvas,
          '${boxSize.toInt()} mm',
          Offset(pos.dx - offsetDistLeft, pos.dy - boxSize),
          Offset(pos.dx - offsetDistLeft, pos.dy),
          isVerticalLine: true,
          isSmall: true,
        );

        double windowHeight = model.height;
        _drawDimension(
          canvas,
          '${windowHeight.toInt()} mm',
          Offset(pos.dx - offsetDistLeft, pos.dy),
          Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
          isVerticalLine: true,
        );
      } else {
        _drawDimension(
          canvas,
          '${boxSize.toInt()} mm',
          Offset(pos.dx - offsetDistLeft, pos.dy),
          Offset(pos.dx - offsetDistLeft, pos.dy + boxSize),
          isVerticalLine: true,
          isSmall: true,
        );

        double windowHeight = model.height - boxSize;
        _drawDimension(
          canvas,
          '${windowHeight.toInt()} mm',
          Offset(pos.dx - offsetDistLeft, pos.dy + boxSize),
          Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
          isVerticalLine: true,
        );
      }
    } else {
      final bool isSlanted =
          model.topSlantLeftY != 0 ||
              model.topSlantRightY != 0 ||
              model.bottomSlantLeftY != 0 ||
              model.bottomSlantRightY != 0;

      double leftH =
          model.height - model.topSlantLeftY - model.bottomSlantLeftY;
      double rightH =
          model.height - model.topSlantRightY - model.bottomSlantRightY;

      double startY = pos.dy + model.topSlantLeftY;
      double endY = pos.dy + model.height - model.bottomSlantLeftY;
      _drawDimension(
        canvas,
        '${leftH.toInt()} mm',
        Offset(pos.dx - offsetDistLeft, startY),
        Offset(pos.dx - offsetDistLeft, endY),
        isVerticalLine: true,
      );

      if (isSlanted) {
        double offsetDistRight = 50.0;
        if (model.hasSideCovers &&
            !model.removedShutterSides.contains('right')) {
          offsetDistRight += scW + 15.0;
        }
        double startYRight = pos.dy + model.topSlantRightY;
        double endYRight = pos.dy + model.height - model.bottomSlantRightY;
        _drawDimension(
          canvas,
          '${rightH.toInt()} mm',
          Offset(pos.dx + model.width + offsetDistRight, startYRight),
          Offset(pos.dx + model.width + offsetDistRight, endYRight),
          isVerticalLine: true,
        );
      }
    }
  }

  void _drawDimension(Canvas canvas,
      String text,
      Offset p1,
      Offset p2, {
        bool isVerticalLine = false,
        bool isSmall = false,
      }) {
    final double midX = (p1.dx + p2.dx) / 2;
    final double midY = (p1.dy + p2.dy) / 2;
    final Offset center = Offset(midX, midY);

    final double textWidth = _drawText(
      canvas,
      text,
      center,
      isVertical: isVerticalLine,
      isSmall: isSmall,
    );

    _drawArrow(
      canvas,
      p1,
      p2,
      isVerticalLine: isVerticalLine,
      textGap: textWidth + 60.0,
    );
  }

  double _drawText(Canvas canvas,
      String text,
      Offset center, {
        bool isVertical = false,
        bool isSmall = false,
      }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.blue.shade900,
          fontWeight: FontWeight.bold,
          fontSize: isSmall ? 46 : 66,
        ),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (isVertical) canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    return tp.width;
  }

  void _drawArrow(Canvas canvas,
      Offset p1,
      Offset p2, {
        bool isVerticalLine = false,
        double textGap = 100.0,
      }) {
    final p = Paint()
      ..color = Colors.blueGrey.shade700
      ..strokeWidth = 2.2;

    double tickSize = 15.0;

    if (isVerticalLine) {
      final double minY = math.min(p1.dy, p2.dy);
      final double maxY = math.max(p1.dy, p2.dy);
      final double midY = (minY + maxY) / 2;
      final double halfGap = textGap / 2;

      // Segment 1 (Top)
      if (midY - halfGap > minY) {
        canvas.drawLine(Offset(p1.dx, minY), Offset(p1.dx, midY - halfGap), p);
      }
      // Segment 2 (Bottom)
      if (maxY > midY + halfGap) {
        canvas.drawLine(Offset(p1.dx, midY + halfGap), Offset(p1.dx, maxY), p);
      }

      // End Ticks
      canvas.drawLine(
        Offset(p1.dx - tickSize, minY),
        Offset(p1.dx + tickSize, minY),
        p,
      );
      canvas.drawLine(
        Offset(p2.dx - tickSize, maxY),
        Offset(p2.dx + tickSize, maxY),
        p,
      );
    } else {
      final double minX = math.min(p1.dx, p2.dx);
      final double maxX = math.max(p1.dx, p2.dx);
      final double midX = (minX + maxX) / 2;
      final double halfGap = textGap / 2;

      // Segment 1 (Left)
      if (midX - halfGap > minX) {
        canvas.drawLine(Offset(minX, p1.dy), Offset(midX - halfGap, p1.dy), p);
      }
      // Segment 2 (Right)
      if (maxX > midX + halfGap) {
        canvas.drawLine(Offset(midX + halfGap, p1.dy), Offset(maxX, p1.dy), p);
      }

      // End Ticks
      canvas.drawLine(
        Offset(minX, p1.dy - tickSize),
        Offset(minX, p1.dy + tickSize),
        p,
      );
      canvas.drawLine(
        Offset(maxX, p2.dy - tickSize),
        Offset(maxX, p2.dy + tickSize),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ProfileButton extends StatelessWidget {
  final String label;
  final String? code;
  final String? imagePath;
  final bool selected;
  final VoidCallback onPressed;

  const _ProfileButton({
    required this.label,
    this.code,
    this.imagePath,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Widget leadingWidget = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SectionImageWidget(
        code: code,
        imagePath: imagePath,
        size: 24.0,
        fallbackIcon: Icons.image_not_supported_rounded,
        fallbackColor: selected ? Colors.blue.shade600 : Colors.grey.shade400,
      ),
    );

    return GestureDetector(
      onTap: onPressed,
      child: Builder(
        builder: (context) {
          final isDark = Theme
              .of(context)
              .brightness == Brightness.dark;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? (isDark
                  ? Colors.blue.shade900.withValues(alpha: 0.3)
                  : Colors.blue.shade50)
                  : (isDark ? const Color(0xFF2E2E3E) : Colors.white),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? Colors.blue
                    : (isDark ? Colors.white24 : Colors.grey.shade300),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leadingWidget,
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white
                        : (selected
                        ? Colors.blue.shade900
                        : Colors.grey.shade800),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Helper validation functions for sliding system glass/gasket thickness constraints (e.g. TPR 67000)
bool isGlassThicknessValid(double thickVal,
    GlassSpecification spec,
    WindowModel model,
    String systemMode,) {
  final String sName =
      model.activeSlidingSeries?.name.toLowerCase() ??
          model.activeSeries?.name.toLowerCase() ??
          '';
  final isTPR67000 =
      sName.contains('67000') || sName.contains('tpr') || sName.contains('tpi');
  final isSliding = systemMode == 'sliding' || model.systemMode == 'sliding';
  if (isSliding && isTPR67000) {
    final double minGasket = spec.jointTwoSides ? 4.0 : 2.0;
    final double maxAllowed = 24.0 - minGasket; // 20.0 or 22.0
    if (thickVal > maxAllowed) return false;
  }
  return true;
}

bool isDoubleGlassValid(double thickOuter,
    int intercall,
    double thickInner,
    bool jointTwoSides,
    WindowModel model,
    String systemMode,) {
  final String sName =
      model.activeSlidingSeries?.name.toLowerCase() ??
          model.activeSeries?.name.toLowerCase() ??
          '';
  final isTPR67000 =
      sName.contains('67000') || sName.contains('tpr') || sName.contains('tpi');
  final isSliding = systemMode == 'sliding' || model.systemMode == 'sliding';
  if (isSliding && isTPR67000) {
    final double minGasket = jointTwoSides ? 4.0 : 2.0;
    final double maxAllowed = 24.0 - minGasket; // 20.0 or 22.0
    if ((thickOuter + intercall + thickInner) > maxAllowed) return false;
  }
  return true;
}
