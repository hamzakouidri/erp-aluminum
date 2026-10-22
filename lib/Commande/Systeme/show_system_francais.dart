// Force compile sync trigger
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:database_data/Commande/Systeme/selling_price_calculator.dart';
import 'package:database_data/Commande/Systeme/installation_fees.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerScrollEvent,
        PointerSignalEvent,
        kLongPressTimeout,
        kMiddleMouseButton,
        kPrimaryMouseButton,
        kSecondaryMouseButton;
import 'package:database_data/widgets/app_material.dart';
import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter,
        HardwareKeyboard,
        KeyEvent,
        KeyDownEvent,
        LogicalKeyboardKey;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/settings/shortcut_bindings.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/Commande/window_3d_preview.dart';
import 'package:database_data/Commande/decor_panel_designs.dart';
import 'package:database_data/Commande/Systeme/model.dart'
    hide getComponentSize;
import 'package:database_data/Commande/Systeme/material_consumption_screen.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart'
    hide getComponentSize;
import 'package:database_data/Commande/Systeme/glass_joint_fit.dart';
import 'package:database_data/Commande/Systeme/corner_notch.dart';
import 'package:database_data/Commande/Systeme/parclose_cut_mode_selector.dart';
import 'package:database_data/Commande/Systeme/glazing_fit_message.dart';
import 'package:database_data/utils/real_color_resolver.dart';
import 'package:database_data/widgets/section_image.dart';
import 'package:database_data/sql_database.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/Commande/Systeme/shutter_calc_rules.dart';
import 'package:database_data/widgets/tunnel_calc_rules_card.dart';
import 'package:database_data/widgets/context_menu_gate.dart';

part 'window_view/shutter_panel.dart';
part 'window_view/glass_panel.dart';
part 'window_view/sliding_panel.dart';
part 'window_view/canvas_interaction.dart';
part 'window_view/toolbars_dialogs.dart';
part 'window_view/drawers.dart';
part 'window_view/frame_controls.dart';
part 'window_view/corner_notch_editor.dart';

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

class _DecorPlacementResult {
  final bool allowed;
  final String? cellId;

  const _DecorPlacementResult(this.allowed, this.cellId);
}

class _WindowViewState extends State<WindowView> {
  /// [setState] for the topic extensions in `window_view/` (a protected
  /// member cannot be called from an extension without a lint).
  void _setViewState(VoidCallback fn) => setState(fn);

  static const _showAllFramesPreferenceKey =
      'drawing_frame_picker_show_all_profiles';
  bool _showAllFrameProfiles = false;

  static const _hidePresetCardPreferenceKey = 'drawing_hide_preset_quick_card';
  bool _hidePresetCard = false;
  // The canvas must never wait for catalogue I/O. A restored model already
  // contains enough geometry to draw immediately, and an empty model can
  // show its workspace while systems/colours load in the background.
  bool _initialCatalogReady = true;






















  Future<List<Map<String, dynamic>>>? _handleCandidates;
  int? _handleSeriesId;


  static const double _minUserScale = 0.5;
  static const double _maxUserScale = 5.0;
  static const double _zoomStep = 1.15;

  String _tr(String key) =>
      Localization.translate(key, context.read<AppSettingsProvider>().language);

  /// A catalogue colour name in the app language.
  String _trColor(Object? name) =>
      Localization.colorName(name, context.read<AppSettingsProvider>().language);








  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// The right mouse button never draws: it moves dimensions, cut-angle
  /// badges, handles and hinges, and anywhere else it moves the view. Only
  /// the left button draws.
  bool get _rightMouseDown =>
      _isWindowsDesktop && (_pointerButtons & kSecondaryMouseButton) != 0;

  /// The tabs that open the left and right drawers exist on the phone only:
  /// on desktop the toolbar button opens the right drawer and a double click
  /// on the drawing (or the glass button) opens the glass drawer.
  static const double _drawerHandleWidth = 28;
  static const double _drawerHandleHeight = 50;



  bool _isDraggingHandle = false;

  /// The mouse buttons of the pointer that started the current drag.
  int _pointerButtons = 0;

  /// Which sliding handle is dragged (left, right, center, center2).
  String? _draggedHandleKey;

  /// A drag with the wheel button only moves the view.
  bool _isMiddlePanning = false;

  /// A left click in progress on the canvas, where and when it was pressed
  /// (null once it moved too far to be a click). With the mouse the drag
  /// recognizer wins after a single pixel, which used to swallow clicks
  /// that moved slightly, so clicks are recognised from the raw pointer.
  ({Offset position, Duration time})? _mouseClickStart;

  /// How far (logical pixels) a mouse click may move and stay a click.
  static const double _mouseClickSlop = 4.0;
  bool _isDraggingHinge = false;
  SashHingeEdge? _draggedHingeEdge;
  int _draggedHingeIndex = 0;
  bool _suppressHandleDragForLongPress = false;
  bool _isDraggingSlantLeft = false;
  DimensionLabelHit? _draggedDimension;

  /// The cut-angle badge being moved (right mouse button on desktop).
  String? _draggedAngleBadge;
  ({String zoneId, String dividerId, bool atStart})? _draggedSlantEnd;
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
  NotchCorner? _draggedNotchCorner;

  /// Corner-cut mode was turned on by a right-button drag only, and ends
  /// with it.
  bool _notchModeFromRightDrag = false;
  String? _draggedFrameZoneId;
  bool _frameResizeHistorySaved = false;
  bool _propertyDragHistorySaved = false;
  final ScrollController _glassScrollController = ScrollController();
  final ScrollController _leftDrawerScrollController = ScrollController();
  final ScrollController _rightDrawerScrollController = ScrollController();
  final TextEditingController _leftSashWidthController =
      TextEditingController();
  final FocusNode _leftSashFocusNode = FocusNode();
  late final TextEditingController _positionCtrl;

  double _userScale = 1.0;
  double _baseUserScale = 1.0;
  Offset _userPan = Offset.zero;
  Offset _baseUserPan = Offset.zero;
  Offset _focalPointStart = Offset.zero;
  // Desktop panning with the middle mouse button or Space + left drag.
  bool _isPanningCanvas = false;

  bool _isDrawerOpen = false;
  bool _isLeftDrawerOpen = false;
  bool _isExitDialogOpen = false;
  bool _isContextMenuOpen = false;


  double _leftDrawerHandleTop = 15.0;
  double _rightDrawerHandleTop = 15.0;

  String? _previousSelectionKey;
  /// When the last canvas tap was released, as the pointer event's own
  /// time stamp: a busy frame after the first tap (the panel opening) no
  /// longer turns a quick double tap into two single taps.
  Duration? _lastTapTime;

  /// Release time of the latest pointer on the canvas (set before the tap
  /// recognizer reports it).
  Duration _lastPointerUpTime = Duration.zero;
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

  /// Height of the page body (under the app bar), measured each layout.
  double _drawingBodyHeight = 0;

  /// Room kept free under the drawing for the open bottom menu (header,
  /// tabs and the 128 px options strip).
  static const double _bottomMenuRoom = 220;

  // ── حالة الضغط على منطقة الستار ──
  bool _isShutterSelected = false;
  int _activeShutterTab =
      0; // 0: شائع, 1: الصندوق, 2: الشفرات, 3: السكك, 4: نوع الستار
  List<Map<String, dynamic>> _shutterLamesOptions = [];
  List<Map<String, dynamic>> _shutterCoulisseOptions = [];
  List<Map<String, dynamic>> _shutterCaissonOptions = [];
  Map<int, String> _unavailableCaissonReasons = {};
  bool _loadingShutterOptions = false;
  double? _lastShutterOptionsHeight;
  int? _lastShutterOptionsBladeId;
  StreamSubscription<String>? _catalogSubscription;
  Timer? _catalogReloadDebounce;

  List<Map<String, dynamic>> _frameProfiles = [];
  List<Map<String, dynamic>> _openingFrameProfiles = [];
  List<Map<String, dynamic>> _slidingFrameProfiles = [];
  List<Map<String, dynamic>> _sashProfiles = [];
  List<Map<String, dynamic>> _openingSashProfiles = [];
  List<Map<String, dynamic>> _slidingSashProfiles = [];
  Set<int> _slidingLateralProfileIds = {};
  Set<int> _slidingCentralProfileIds = {};
  int? _loadedSeriesId;
  int? _loadedOpeningFrameSeriesId;
  int? _loadedSlidingFrameSeriesId;
  bool _loadingAvailableProfiles = false;
  int _profileLoadGeneration = 0;
  static final Map<String, _CachedProfiles> _profilesMemoryCache = {};
  bool _slidingSeriesAutoSelectionQueued = false;
  bool _openingSeriesAutoSelectionQueued = false;

  // Drawing actions can generate far more pointer events than the display can
  // render.  Keep the full controls page at one refresh per frame; the canvas
  // itself listens to the model and remains immediate.
  bool _modelUiRefreshQueued = false;















  Future<bool> _paintZoneContentFromUi(
    WindowZone zone,
    ZoneContent content, {
    int? slidingSashesCount,
  }) async {
    bool? cutRebate;
    if (content == ZoneContent.slidingSash) {
      if (widget.model.hasArchOrSlant) {
        _showSlidingUnsupportedSnack();
        return false;
      }
      cutRebate = await _askSlidingRebateCut(zone);
      if (!mounted) return false;
    }
    widget.model.paintZoneContent(
      zone.id,
      content,
      slidingSashesCount: slidingSashesCount,
      cutSlidingGlassRebate: cutRebate,
    );
    return true;
  }








  void _onModelChanged() {
    // A regular window can have both zones and a shutter. Catalogue refreshes
    // must not dismiss the shutter panel simply because those zones exist.
    if (_isShutterSelected &&
        !widget.model.isShutterOnly &&
        !widget.model.hasShutter) {
      _isShutterSelected = false;
    }
    final selection = widget.model.selection;
    final currentSelectionKey = _currentSelectionKey();
    final selectionChanged = currentSelectionKey != _previousSelectionKey;
    if (selectionChanged) {
      if (selection.type == null) {
        _isLeftDrawerOpen = false;
        _isDrawerOpen = false;
        _isBottomPanelExpanded = false;
      } else {
        // Selecting any drawing element opens its contextual bottom panel.
        // If the panel is already open, keep the tab the user just chose.
        // Resetting it to "Common" here made the first tap on Frame, Ouvrant
        // or any other tab appear to open and immediately close.
        final wasExpanded = _isBottomPanelExpanded;
        _isShutterSelected = false;
        _isBottomPanelExpanded = true;
        if (!wasExpanded) {
          if (selection.type == SelectionType.frame) {
            _activeBottomTab = 1;
          } else if (selection.type == SelectionType.mullion) {
            _activeBottomTab = 3;
          } else {
            _activeBottomTab = 0;
          }
        } else if (selection.type == SelectionType.frame) {
          _activeBottomTab = 1;
        } else if (selection.type == SelectionType.mullion) {
          _activeBottomTab = 3;
        }
      }
      _previousSelectionKey = currentSelectionKey;
    }

    // The preview has its own repaint listener. While drawing a new frame or
    // dragging any handle/divider/hinge/division, rebuilding the drawers and
    // running database scans on every mouse movement was the main source of lag.
    final isAnyDragActive =
        widget.model.drawingStart != null ||
        _isDraggingHandle ||
        _isDraggingHinge ||
        _isDraggingDoubleSashDivider ||
        _isDraggingSashDivision ||
        _isDraggingDecor ||
        _isDraggingSlantLeft ||
        _isDraggingSlantRight ||
        _isDraggingArch ||
        _draggedFrameResizeHandle != null ||
        _draggedNotchCorner != null;
    if (isAnyDragActive && !selectionChanged) {
      return;
    }

    if (selectionChanged) {
      // A selection click changes only editor chrome (active toolbar/panel).
      // Do not rescan every zone's glass or check/reload profile catalogues;
      // those values did not change and the scans made frame selection lag.
      setState(() {});
      return;
    }

    _queueModelUiRefresh();
  }

  void _queueModelUiRefresh() {
    if (_modelUiRefreshQueued || !mounted) return;
    _modelUiRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _modelUiRefreshQueued = false;
      if (!mounted) return;
      _refreshModelDependentUi();
      setState(() {});
    });
  }

  void _refreshModelDependentUi() {
    _syncDrawerGlassFromDrawing();
    final rawBlade = widget.model.componentOverrides['الشرائح (Lames)'];
    final rawBladeId = rawBlade is Map ? rawBlade['id'] : null;
    final bladeId = rawBladeId is num
        ? rawBladeId.toInt()
        : int.tryParse(rawBladeId?.toString() ?? '');
    if (widget.model.hasShutter &&
        (_lastShutterOptionsHeight != widget.model.height ||
            _lastShutterOptionsBladeId != bladeId)) {
      _lastShutterOptionsHeight = widget.model.height;
      _lastShutterOptionsBladeId = bladeId;
      unawaited(_loadShutterOptions());
    }

    final openingSeriesId = widget.model.activeSeries?.id;
    final slidingSeriesId = widget.model.activeSlidingSeries?.id;
    final needsOpeningFrames =
        widget.systemMode == 'mixed' && openingSeriesId != null;
    final needsSlidingFrames =
        (widget.systemMode == 'mixed' || widget.systemMode == 'sliding') &&
        slidingSeriesId != null;
    if (activeSeriesForSystem?.id != _loadedSeriesId ||
        (needsOpeningFrames &&
            _loadedOpeningFrameSeriesId != openingSeriesId) ||
        (needsSlidingFrames &&
            _loadedSlidingFrameSeriesId != slidingSeriesId)) {
      unawaited(_loadAvailableProfiles());
    }
  }




  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_hingeKeyHandler);
    _drawingTimer?.cancel();
    _paintbrushTimer?.cancel();
    _catalogReloadDebounce?.cancel();
    _catalogSubscription?.cancel();
    widget.model.removeListener(_onModelChanged);
    _glassScrollController.dispose();
    _leftDrawerScrollController.dispose();
    _rightDrawerScrollController.dispose();
    _leftSashWidthController.dispose();
    _leftSashFocusNode.dispose();
    _positionCtrl.dispose();
    super.dispose();
  }

  Null get items => null;











  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_hingeKeyHandler);
    // Any model opened through the full design workspace must return here
    // when it is edited, including designs that use a tunnel box or wall.
    widget.model.isDesignDrawing = true;
    _positionCtrl = TextEditingController(text: widget.model.position ?? '');
    widget.model.addListener(_onModelChanged);
    _syncDrawerGlassFromDrawing();
    // Models opened for editing normally inherit the already loaded catalogue.
    // Re-querying it here used to show a default series for a few seconds and,
    // when no active series existed yet, the same expensive load ran twice.
    final hasReusableCatalog =
        widget.model.availableSystems.isNotEmpty &&
        (widget.model.activeSeries != null ||
            widget.model.activeSlidingSeries != null);
    _initialCatalogReady = true;
    if (!hasReusableCatalog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadInitialCatalog());
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadShutterOptions());
    }); // Preload without delaying the first canvas frame.
    _catalogSubscription = CloudSyncService().dbUpdateStream.listen((update) {
      const catalogUpdates = {
        'catalog_changed',
        'catalog_downloaded',
        'cloud_restored',
        // Supabase workshop rows are applied to SQLite in the background.
        // Reload this page too, otherwise the first opened drawing keeps the
        // empty colour list until the user changes series manually.
        'supabase_data_updated',
      };
      if (!catalogUpdates.contains(update)) {
        return;
      }
      _catalogReloadDebounce?.cancel();
      _catalogReloadDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        unawaited(widget.model.loadCatalogData(widget.systemMode));
        // The cache is shared by every drawing; profiles edited or
        // downloaded keep their id, so the old entries must not be reused.
        _profilesMemoryCache.clear();
        _loadedSeriesId = null;
        unawaited(_loadAvailableProfiles());
        _loadShutterOptions();
      });
    });
    SharedPreferences.getInstance().then((prefs) {
      final name = prefs.getString('workshop_name');
      if (name != null && name.trim().isNotEmpty) {
        widget.model.workshopName = name;
        widget.model.refreshUI();
      }
      final showAllFrames = prefs.getBool(_showAllFramesPreferenceKey) ?? false;
      if (mounted && showAllFrames != _showAllFrameProfiles) {
        setState(() => _showAllFrameProfiles = showAllFrames);
      }
      final hidePreset = prefs.getBool(_hidePresetCardPreferenceKey) ?? false;
      if (mounted && hidePreset != _hidePresetCard) {
        setState(() => _hidePresetCard = hidePreset);
      }
    });
    // Touch devices start in move mode; Windows starts in design mode.
    widget.model.setDrawingMode(_isWindowsDesktop);
  }
















  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final hasSelection = widget.model.selectedZone != null;
    final isMullionSelected =
        widget.model.selection.type == SelectionType.mullion;
    final isInnerDivisionSelected =
        widget.model.selection.type == SelectionType.innerDivision;
    final isFrameSelected =
        widget.model.selection.type == SelectionType.frame &&
        widget.model.getFrameRects().length > 1;

    Widget? activeTopToolbar;
    if (isInnerDivisionSelected) {
      activeTopToolbar = _buildInnerDivisionToolbar(context);
    } else if (isFrameSelected) {
      activeTopToolbar = _buildFrameToolbar(context);
    } else if (isMullionSelected) {
      activeTopToolbar = _buildMullionToolbar(context);
    } else if (!_isWindowsDesktop) {
      activeTopToolbar = _buildSplitToolbar(context, hasSelection);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmExitFromDrawing());
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E2C)
            : const Color(0xFFE8EAF6),
        appBar: _buildAppBar(context),
        body: !_initialCatalogReady
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, bodyConstraints) {
                  _drawingBodyHeight = bodyConstraints.maxHeight;
                  return Stack(
                children: [
                  Column(
                    children: [
                      if (widget.model.shutterWidthWarning != null)
                        Container(
                          key: const ValueKey('drawing-shutter-width-warning'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: Colors.orange.shade100,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade900,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.model.localizedShutterWidthWarning(
                                        lang,
                                      ) ??
                                      widget.model.shutterWidthWarning!,
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (widget.model.recommendedShutterBlade !=
                                  null) ...[
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade800,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                  ),
                                  label: Text(
                                    lang == AppLanguage.french
                                        ? 'Appliquer la lame recommandée'
                                        : (lang.fallback == AppLanguage.english
                                              ? 'Apply recommended blade'
                                              : 'تطبيق الشفرة المقترحة'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () async {
                                    widget.model.applyRecommendedShutterBlade();
                                    await widget.model
                                        .updateShutterDefaultsIfNeeded();
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),

                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // The bottom menu shrinks this canvas when it
                            // opens. The camera fits a fixed working area
                            // above the room the menu takes, so opening or
                            // closing it never moves the drawing.
                            final menuRoom = math.min(
                              _bottomMenuRoom +
                                  MediaQuery.paddingOf(context).bottom,
                              _drawingBodyHeight * 0.3,
                            );
                            widget.model.updateLayoutMetrics(
                              Size(
                                constraints.maxWidth,
                                math.max(
                                  100.0,
                                  _drawingBodyHeight - menuRoom,
                                ),
                              ),
                            );
                            // A tap or click on the canvas: selects what is under it.
                            Future<void> handleCanvasTap(
                              TapUpDetails details,
                            ) async {
                                    final modelPos = _getModelPos(
                                      details.localPosition,
                                    );
                                    final tappedHinge = _hingeAt(
                                      details.localPosition,
                                      );
                                    if (tappedHinge != null) {
                                      _selectHinge(tappedHinge);
                                      return;
                                      }
                                    if (widget.model.selectedHinge != null) {
                                      widget.model.selectHinge(null);
                                      }

                                    // Slanted mullion: the first tap selects
                                    // it (end handles appear), a tap on the
                                    // selected one opens its editor.
                                    final slantHit = widget.model
                                        .slantedDividerAt(
                                          modelPos,
                                          slopMm:
                                              8.0 /
                                              (widget.model.canvasScale *
                                                  _userScale),
                                        );
                                    if (slantHit != null) {
                                      if (widget.model
                                              .selectedSlantedDivider ==
                                          slantHit) {
                                        _showSlantedDividerDialog(slantHit);
                                        } else {
                                        widget.model.selectSlantedDivider(
                                          slantHit,
                                            );
                                          }
                                      return;
                                        }
                                    if (widget.model.selectedSlantedDivider !=
                                        null) {
                                      widget.model.selectSlantedDivider(null);
                                      }

                                    // --- Individual frame dimension tap (coupled windows) ---
                                    // First check the number painted directly in
                                    // a frame profile.  This is intentionally
                                    // narrower than the surrounding profile.
                                    InnerDimensionHit? individualTap =
                                        _frameProfileDimensionHit(modelPos);
                                    // Each coupled frame's own width/height
                                    // number, exactly where it was painted.
                                      if (individualTap == null) {
                                      final key = widget.model
                                          .dimensionLabelAt(modelPos)
                                          ?.key;
                                      if (key != null &&
                                          (key.startsWith('frameW:') ||
                                              key.startsWith('frameH:'))) {
                                            individualTap = InnerDimensionHit(
                                          key.substring('frameW:'.length),
                                          key.startsWith('frameW:'),
                                            );
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

                                    // Opening the glass drawer is not an apply
                                    // command. Only an explicitly armed paintbrush
                                    // may write a glass specification to a zone.
                                    if (_paintbrushSecondsLeft > 0) {
                                      // A prepared zone type has priority over
                                      // the glass brush. This makes a choice such
                                      // as "double sash" apply to the frame that
                                      // is clicked next.
                                      if (_activePaintZoneContent != null) {
                                        WindowZone? tappedZ;
                                        for (final zone in widget.model.zones) {
                                          if (zone.boundary.contains(
                                            modelPos,
                                          )) {
                                            tappedZ = zone;
                                            break;
                                          }
                                        }
                                        if (tappedZ != null) {
                                          final applied =
                                              await _paintZoneContentFromUi(
                                                tappedZ,
                                                _activePaintZoneContent!,
                                                slidingSashesCount:
                                                    _activePaintSlidingSashesCount,
                                              );
                                          if (applied) {
                                            setState(() {
                                              _paintbrushSecondsLeft = 10;
                                            });
                                            return;
                                          }
                                        }
                                      }
                                      final specToApply = _activePaintGlassSpec;
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
                                          if (isDouble ||
                                              isSingle ||
                                              isSliding) {
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
                                                for (var sec
                                                    in series.sections) {
                                                  final secType = sec.type
                                                      .toLowerCase();
                                                  if (secType == 'chicane' ||
                                                      secType ==
                                                          'sash_central' ||
                                                      secType == 'central' ||
                                                      secType == 'centrale') {
                                                    if (sec.visibleWidth > 0) {
                                                      chicaneT =
                                                          sec.visibleWidth;
                                                    } else if (sec.thickness >
                                                        0)
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
                                                for (
                                                  int i = 0;
                                                  i < count;
                                                  i++
                                                ) {
                                                  if (tracks[i] == tg) {
                                                    double left =
                                                        tappedZ.boundary.left +
                                                        i *
                                                            (sashWidth -
                                                                chicaneT);
                                                    Rect
                                                    sashRect = Rect.fromLTRB(
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
                                                if (selectedSashIndex != -1)
                                                  break;
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
                                              final glassR = sashR.deflate(
                                                sashT,
                                              );
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
                                                final clampedX = modelPos.dx
                                                    .clamp(
                                                      glassR.left + 0.1,
                                                      glassR.right - 0.1,
                                                    );
                                                final clampedY = modelPos.dy
                                                    .clamp(
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
                                                    ? (isRight
                                                          ? 'right'
                                                          : 'left')
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
                                            tappedCellId =
                                                'main_cell_${row}_$col';
                                          }
                                          var targetCellId = tappedCellId;
                                          if (_isDecorPanelSpec(specToApply)) {
                                            final placement =
                                                await _prepareDecorPanelPlacement(
                                                  zone: tappedZ,
                                                  cellId: tappedCellId,
                                                  spec: specToApply,
                                                );
                                            if (!placement.allowed) return;
                                            targetCellId = placement.cellId;
                                          }
                                          widget.model.paintZoneOrCellSpec(
                                            tappedZ.id,
                                            spec: specToApply,
                                            cellId: targetCellId,
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
                                          if (isDouble ||
                                              isSingle ||
                                              isSliding) {
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
                                              int currentInnerH =
                                                  tappedZ.innerH;
                                              int currentInnerV =
                                                  tappedZ.innerV;
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
                                      } else if (_activePaintZoneContent !=
                                          null) {
                                        WindowZone? tappedZ;
                                        for (var z in widget.model.zones) {
                                          if (z.boundary.contains(modelPos)) {
                                            tappedZ = z;
                                            break;
                                          }
                                        }
                                        if (tappedZ != null) {
                                          final applied =
                                              await _paintZoneContentFromUi(
                                                tappedZ,
                                                _activePaintZoneContent!,
                                                slidingSashesCount:
                                                    _activePaintSlidingSashesCount,
                                              );
                                          if (applied) return;
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

                                    if (_handleCornerNotchLabelTap(
                                      details.localPosition,
                                    )) {
                                      return;
                                    }
                                    final handleLabelZone = widget.model
                                        .handleHeightLabelAt(modelPos);
                                    if (handleLabelZone != null) {
                                      _showHandleHeightDialog(handleLabelZone);
                                      return;
                                    }
                                    final headDimension = widget.model
                                        .dimensionLabelAt(modelPos)
                                        ?.key;
                                    if (headDimension == 'leftJamb' ||
                                        headDimension == 'rightJamb' ||
                                        headDimension == 'archRise') {
                                      _showHeadDimensionDialog(headDimension!);
                                      return;
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
                                    double nearestMullionDistance =
                                        double.infinity;
                                    double hitSlop = 40.0;
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
                                        final z1 =
                                            widget.model.zones[i].boundary;
                                        final z2 =
                                            widget.model.zones[j].boundary;
                                        if (widget.model.isMullionGapBetween(true, z1.bottom, z2.top) ||
                                            widget.model.isMullionGapBetween(true, z2.bottom, z1.top)) {
                                          double yCenter =
                                              (z1.bottom + z2.top) / 2;
                                          if (widget.model.isMullionGapBetween(true, z2.bottom, z1.top)) {
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
                                            final distance =
                                                (modelPos.dy - yCenter).abs();
                                            if (distance <
                                                nearestMullionDistance) {
                                              tappedMullion = true;
                                              tappedMullionIsHorizontal = true;
                                              tappedMullionPosition = yCenter;
                                              nearestMullionDistance = distance;
                                            }
                                          }
                                        }
                                        if (widget.model.isMullionGapBetween(false, z1.right, z2.left) ||
                                            widget.model.isMullionGapBetween(false, z2.right, z1.left)) {
                                          double xCenter =
                                              (z1.right + z2.left) / 2;
                                          if (widget.model.isMullionGapBetween(false, z2.right, z1.left)) {
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
                                            final distance =
                                                (modelPos.dx - xCenter).abs();
                                            if (distance <
                                                nearestMullionDistance) {
                                              tappedMullion = true;
                                              tappedMullionIsHorizontal = false;
                                              tappedMullionPosition = xCenter;
                                              nearestMullionDistance = distance;
                                            }
                                          }
                                        }
                                      }
                                    }

                                    final now = _lastPointerUpTime;
                                    bool isDoubleTap = false;
                                    if (_lastTapTime != null &&
                                        now - _lastTapTime! <
                                            const Duration(milliseconds: 450)) {
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
                                    final frameKeyBeforeTap =
                                        widget.model.selectedFrameKey;
                                    // One tap on a frame: green resize squares.
                                    // A second quick tap on it: orange slant/arch
                                    // circles (a sliding window says why not).
                                    void updateFrameShapeMode() {
                                      widget.model.applyFrameTapMode(
                                        isDoubleTap: isDoubleTap,
                                        frameKeyBeforeTap: frameKeyBeforeTap,
                                      );
                                      if (isDoubleTap &&
                                          frameKeyBeforeTap != null &&
                                          widget.model.selectedFrameKey ==
                                              frameKeyBeforeTap &&
                                          !widget.model.canBeArchedOrSlanted) {
                                        ScaffoldMessenger.of(context)
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                _tr(
                                                  'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                                ),
                                              ),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                      }
                                    }

                                    final frameAtBorderHit = _frameAtBorder(
                                      modelPos,
                                    );
                                    if (!tappedZone &&
                                        !tappedMullion &&
                                        frameAtBorderHit == null &&
                                        outerTap == DimensionTap.none &&
                                        innerTap == null &&
                                        mullionDimTap == null) {
                                      // The view never moves on its own, not
                                      // even on a double click here: only the
                                      // wheel, a drag or the centre button. A
                                      // double click just under the frame
                                      // still shows or hides the bottom wall.
                                      final h = widget.model.height;
                                      if (isDoubleTap &&
                                          modelPos.dx >= 0 &&
                                          modelPos.dx <= widget.model.width &&
                                          modelPos.dy >= h &&
                                          modelPos.dy <= h + 250.0) {
                                        widget.model.toggleBottomWall();
                                        return;
                                      }
                                      setState(() {
                                        _isDrawerOpen = false;
                                        _isLeftDrawerOpen = false;
                                        _isBottomPanelExpanded = false;
                                        _isShutterSelected = false;
                                      });
                                      widget.model.clearSelection();
                                      return;
                                    }

                                    if (outerTap != DimensionTap.none) {
                                      _showResizeDialog(
                                        context,
                                        focusWidth:
                                            outerTap == DimensionTap.width,
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
                                      // Under the frame (not on its bottom
                                      // profile, which shows the orange circles).
                                      if (frameAtBorderHit == null &&
                                          modelPos.dy >= h - 30.0 &&
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
                                          modelPos.dx <=
                                              widget.model.width + 20) {
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
                                    final frameAtBorder = _frameAtBorder(
                                      modelPos,
                                    );
                                    if (frameAtBorder != null) {
                                      setState(() {
                                        _isShutterSelected = false;
                                        _isBottomPanelExpanded = true;
                                      });
                                      widget.model.selectFrameByIndex(
                                        frameAtBorder,
                                      );
                                      updateFrameShapeMode();
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
                                    updateFrameShapeMode();

                                    if (!widget.model.isShutterOnly &&
                                        isDoubleTap &&
                                        tappedZone) {
                                      setState(() {
                                        widget.model.clearSelection();
                                        _isLeftDrawerOpen = true;
                                      });
                                    }
                            }

                            return Stack(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    // Mouse clicks come from the Listener
                                    // below, which also keeps a click that
                                    // moved a pixel or two.
                                    if (details.kind !=
                                        PointerDeviceKind.mouse) {
                                      handleCanvasTap(details);
                                    }
                                  },
                                  onSecondaryTapUp: (details) => ContextMenuGate.run<void>(() async {
                                    if (await _showHingeContextMenu(
                                      details.globalPosition,
                                      details.localPosition,
                                    )) {
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    await _showDesktopContextMenu(
                                      context,
                                      details.globalPosition,
                                      details.localPosition,
                                    );
                                  }),
                                  onLongPressStart: (details) async {
                                    widget.model.holdCamera = true;
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
                                    if (tappedZ != null &&
                                        (tappedZ.content ==
                                                ZoneContent.singleSash ||
                                            tappedZ.content ==
                                                ZoneContent.doubleSash ||
                                            tappedZ.content ==
                                                ZoneContent.slidingSash)) {
                                      _suppressHandleDragForLongPress = true;
                                      _isDraggingHandle = false;
                                      _isDraggingHinge = false;
                                    }

                                    if (_paintbrushSecondsLeft > 0) {
                                      // A long press applies to all zones only when
                                      // the user explicitly selected a glass brush.
                                      // Never reuse the currently saved zone glass
                                      // merely because the drawer is open.
                                      final specToApply = _activePaintGlassSpec;
                                      if (specToApply != null &&
                                          tappedZ != null) {
                                        unawaited(
                                          widget.model
                                              .applyGlassSpecificationToAllZones(
                                                specToApply,
                                              ),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              _tr(
                                                'تم تعميم نوع البانو/الزجاج على جميع المناطق',
                                              ),
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
                                      widget.model
                                          .deleteSelectedInnerDivision();
                                      return;
                                    }
                                    if (widget.model.selection.type ==
                                        SelectionType.frame) {
                                      if (widget.model.getFrameRects().length >
                                          1) {
                                        widget.model.deleteSelectedFrame();
                                        return;
                                      }
                                      if (widget.model.canBeArchedOrSlanted) {
                                        widget.model.selection = SelectionInfo(
                                          type: SelectionType.frame,
                                        );
                                        // The long press announces the
                                        // slant/arch circles: show them.
                                        widget.model.frameShapeMode = true;
                                        widget.model.showZoneMenu = false;
                                        widget.model.activeSubZone = null;
                                        widget.model.refreshUI();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).hideCurrentSnackBar();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(
                                                  Icons.gesture_rounded,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _tr(
                                                      'تم تفعيل وضع تعديل ميلان وتقويس الإطار (اسحب المقابض الدائرية العلوية)',
                                                    ),
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor:
                                                Colors.amber.shade900,
                                            duration: const Duration(
                                              milliseconds: 2200,
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        return;
                                      }
                                    }

                                    final zone = widget.model.selectedZone;
                                    final cellKey = widget.model.activeSubZone;
                                    final isCellSash =
                                        zone != null &&
                                        cellKey != null &&
                                        cellKey.contains('_cell_') &&
                                        (zone.cellIsSash[cellKey] == true ||
                                            zone.cellIsDoubleSash[cellKey] ==
                                                true);
                                    if (!isCellSash &&
                                        widget.model.allSashesSelected) {
                                      widget.model.refreshUI();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).hideCurrentSnackBar();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _tr(
                                              'تم تحديد كل الضلفات: الظلفة والمقبض يتغيران فيها كلها. ضغطة واحدة تحدد ضلفة واحدة.',
                                            ),
                                          ),
                                          duration: const Duration(
                                            milliseconds: 2500,
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                    if (zone != null &&
                                        cellKey != null &&
                                        cellKey.contains('_cell_')) {
                                      final hasSash = isCellSash;
                                      if (hasSash) {
                                        final selected =
                                            await showDialog<
                                              Map<String, dynamic>
                                            >(
                                              context: context,
                                              builder: (context) =>
                                                  ProfileSelectorDialog(
                                                    profileType: 'sash',
                                                    seriesId:
                                                        activeSeriesForSystem
                                                            ?.id,
                                                    hasSimpleGlassForReducer: widget
                                                        .model
                                                        .hasSimpleGlassForReducer,
                                                    hasDoubleGlassForRules: widget
                                                        .model
                                                        .hasDoubleGlassForRules,
                                                  ),
                                            );
                                        if (!mounted || selected == null)
                                          return;
                                        final mutableSelected =
                                            Map<String, dynamic>.from(selected);
                                        mutableSelected['calculated_price'] =
                                            await _sectionPriceForSelectedColor(
                                              mutableSelected,
                                            );
                                        if (!mounted) return;

                                        setState(() {
                                          final newOverrides =
                                              Map<
                                                String,
                                                Map<String, dynamic>
                                              >.from(zone.cellSashOverrides);
                                          newOverrides[cellKey] =
                                              mutableSelected;
                                          zone.cellSashOverrides = newOverrides;
                                          widget.model.refreshUI();
                                        });
                                      }
                                    }
                                  },
                                  onLongPressMoveUpdate: (details) {
                                    if (widget.model.selectedZone?.content ==
                                            ZoneContent.doubleSash &&
                                        widget.model.activeSubZone == 'all' &&
                                        widget.model.isDrawingMode) {
                                      if (!_propertyDragHistorySaved) {
                                        widget.model.saveSnapshotOutside();
                                        _propertyDragHistorySaved = true;
                                      }
                                      final zone = widget.model.selectedZone!;
                                      final bounds = zone.boundary;
                                      final modelPos = _getModelPos(
                                        details.localPosition,
                                      );
                                      double newRatio =
                                          (modelPos.dx - bounds.left) /
                                          bounds.width;
                                      newRatio = newRatio.clamp(0.15, 0.85);
                                      widget.model.updateZoneDoubleSashRatio(
                                        zone.id,
                                        _storedDoubleSashRatio(newRatio),
                                        saveHistory: false,
                                      );
                                    }
                                  },
                                  onLongPressEnd: (details) {
                                    _isDraggingHandle = false;
                                    _isDraggingHinge = false;
                                    _suppressHandleDragForLongPress = false;
                                    _propertyDragHistorySaved = false;
                                    setState(
                                      () => widget.model.holdCamera = false,
                                    );
                                  },
                                  onScaleStart: (details) {
                                    widget.model.holdCamera = true;
                                    if (_isDrawerOpen || _isLeftDrawerOpen) {
                                      setState(() {
                                        _isDrawerOpen = false;
                                        _isLeftDrawerOpen = false;
                                      });
                                    }
                                    _baseUserScale = _userScale;
                                    _baseUserPan = _userPan;
                                    _focalPointStart = details.localFocalPoint;
                                    _draggedHandleKey = null;
                                    if ((_pointerButtons & kMiddleMouseButton) !=
                                        0) {
                                      _isMiddlePanning = true;
                                      return;
                                    }

                                    if (_isWindowsDesktop &&
                                        HardwareKeyboard
                                            .instance
                                            .logicalKeysPressed
                                            .contains(
                                              LogicalKeyboardKey.space,
                                            )) {
                                      _isPanningCanvas = true;
                                      return;
                                    }
                                    if (details.pointerCount < 2) {
                                      final modelPos = _getModelPos(
                                        details.localFocalPoint,
                                      );

                                      // Grabbing a dimension number moves its
                                      // whole row away from (or back to) the
                                      // frame; nothing in the design changes.
                                      // A cut-angle badge moves with the
                                      // right mouse button (a finger on a
                                      // phone) when it covers something.
                                      final badge = widget.model
                                          .angleBadgeAt(modelPos);
                                      if (badge != null &&
                                          (!_isWindowsDesktop ||
                                              _rightMouseDown)) {
                                        _draggedAngleBadge = badge;
                                        return;
                                      }
                                      // Dimensions move with the right
                                      // button (a finger on a phone); a
                                      // left-button drag on a number does
                                      // nothing (it must not start drawing).
                                      final grabbed = widget.model
                                          .dimensionLabelAt(modelPos);
                                      if (grabbed != null &&
                                          grabbed.dragKey.isNotEmpty &&
                                          grabbed.normal != Offset.zero) {
                                        if (!_isWindowsDesktop ||
                                            _rightMouseDown) {
                                          _draggedDimension = grabbed;
                                        }
                                        return;
                                      }
                                      // An end handle of the selected slanted
                                      // mullion slides along the zone sides.
                                      final slantEnd = _slantEndAt(
                                        details.localFocalPoint,
                                      );
                                      if (slantEnd != null) {
                                        _draggedSlantEnd = slantEnd;
                                        return;
                                      }

                                      if (_startHingeDrag(details)) return;

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
                                      // Grab the arch on its apex (the arc
                                      // midpoint); a flat head offers the
                                      // middle of the top edge.
                                      final tcScreen = modelToScreen(
                                        widget.model.headArc()?.apex ??
                                        Offset(
                                          widget.model.width / 2,
                                              (widget.model.topSlantLeftY +
                                                      widget
                                                          .model
                                                          .topSlantRightY) /
                                                  2,
                                        ),
                                      );
                                      final touchScreen =
                                          details.localFocalPoint;
                                      const double hitRadius = 35.0;

                                      if (_startCornerNotchRightDrag(
                                        touchScreen,
                                      )) {
                                        return;
                                      }
                                      final notchHandle =
                                          _cornerNotchHandleAt(touchScreen);
                                      if (notchHandle != null) {
                                        _draggedNotchCorner = notchHandle;
                                        return;
                                      }
                                      final frameResizeHandle =
                                          _frameResizeHandleAt(touchScreen);
                                      final canSlantOrArch =
                                          widget.model.frameShapeMode &&
                                          widget.model.canShapeSelectedFrame;
                                      if (frameResizeHandle != null) {
                                        _draggedFrameResizeHandle =
                                            frameResizeHandle;
                                        _draggedFrameZoneId =
                                            widget.model.selection.zoneId ??
                                            'frame:0';
                                        _frameResizeHistorySaved = false;
                                      } else if (canSlantOrArch &&
                                          (touchScreen - tlScreen).distance <
                                              hitRadius) {
                                        _isDraggingSlantLeft = true;
                                      } else if (canSlantOrArch &&
                                          (touchScreen - trScreen).distance <
                                              hitRadius) {
                                        _isDraggingSlantRight = true;
                                      } else if (canSlantOrArch &&
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
                                        final canInteractWithHardware =
                                            widget.model.isInternalView ||
                                            widget.model.showInternalHardware;
                                        final bool isDoubleBothSelected =
                                            zone.content ==
                                                ZoneContent.doubleSash &&
                                            widget.model.activeSubZone == 'all';

                                        if (canInteractWithHardware &&
                                            (zone.content ==
                                                    ZoneContent.singleSash ||
                                                zone.content ==
                                                    ZoneContent.doubleSash)) {
                                          final activeIsRight =
                                              widget.model.activeSubZone !=
                                                      null &&
                                                  widget.model.activeSubZone !=
                                                      'all'
                                              ? widget.model.activeSubZone!
                                                    .startsWith('right')
                                              : (zone.openDirection !=
                                                    OpenDirection.left);

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

                                          // Precise hit testing for handle - disabled when both sashes are selected!
                                          if (!isDoubleBothSelected ||
                                              (_pointerButtons &
                                                      kSecondaryMouseButton) !=
                                                  0) {
                                            double hRatio =
                                                zone.handlePositionRatio ?? 0.5;
                                            double hX = sashRect.center.dx;
                                            double hY = sashRect.center.dy;

                                            if (handleSide ==
                                                OpenDirection.left) {
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

                                            final handleScreenPos =
                                                modelToScreen(Offset(hX, hY));
                                            if ((touchScreen - handleScreenPos)
                                                    .distance <
                                                45.0) {
                                              _isDraggingHandle = true;
                                              hitHandle = true;
                                            }
                                          }

                                        } else if (canInteractWithHardware &&
                                            zone.content ==
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
                                          final hRatioLeft = zone
                                              .handleRatioFor('left');
                                          final hRatioRight = zone
                                              .handleRatioFor('right');

                                          // Left handle (OpenDirection.left on sashRectLeft)
                                          double hXLeft =
                                              sashRectLeft.left + 20;
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
                                                  (1.0 - hRatioLeft));

                                          // Right handle (OpenDirection.right on sashRectRight)
                                          double hXRight =
                                              sashRectRight.right - 20;
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
                                                  (1.0 - hRatioRight));

                                          final handleScreenPosLeft =
                                              modelToScreen(
                                                Offset(hXLeft, hYLeft),
                                              );
                                          final handleScreenPosRight =
                                              modelToScreen(
                                                Offset(hXRight, hYRight),
                                              );

                                          final onLeftHandle =
                                              (touchScreen -
                                                          handleScreenPosLeft)
                                                      .distance <
                                                  45.0;
                                          final onRightHandle =
                                              (touchScreen -
                                                          handleScreenPosRight)
                                                      .distance <
                                                  45.0;
                                          var touchesSlidingHandle =
                                              onLeftHandle || onRightHandle;
                                          if (onLeftHandle) {
                                            _draggedHandleKey = 'left';
                                          } else if (onRightHandle) {
                                            _draggedHandleKey = 'right';
                                          }

                                          final hasCentralMeeting =
                                              zone.slidingFaceToFace &&
                                              count >= 4 &&
                                              count.isEven;
                                          if (!touchesSlidingHandle &&
                                              hasCentralMeeting) {
                                            final centerX = bounds.center.dx;
                                            final mainHandleOnRight =
                                                zone.openDirection !=
                                                OpenDirection.left;

                                            Offset centralHandlePosition(
                                              bool onRight,
                                              String key,
                                            ) {
                                              final hRatio = zone
                                                  .handleRatioFor(key);
                                              final x = onRight
                                                  ? centerX + 20.0
                                                  : centerX - 20.0;
                                              final topY = getSashTopY(
                                                x,
                                                bounds.top,
                                                widget.model.profileThickness,
                                                topOffset,
                                                isTopBound,
                                              );
                                              final y =
                                                  topY +
                                                  ((bounds.bottom - topY) *
                                                      (1.0 - hRatio));
                                              return modelToScreen(
                                                Offset(x, y),
                                              );
                                            }

                                            if (zone.slidingCentralHandle ||
                                                zone.slidingFaceToFace) {
                                              touchesSlidingHandle =
                                                  (touchScreen -
                                                          centralHandlePosition(
                                                            mainHandleOnRight,
                                                            'center',
                                                          ))
                                                      .distance <
                                                  45.0;
                                              if (touchesSlidingHandle) {
                                                _draggedHandleKey = 'center';
                                              }
                                            }
                                            if (!touchesSlidingHandle &&
                                                zone.slidingSecondCentralHandle) {
                                              touchesSlidingHandle =
                                                  (touchScreen -
                                                          centralHandlePosition(
                                                            !mainHandleOnRight,
                                                            'center2',
                                                          ))
                                                      .distance <
                                                  45.0;
                                              if (touchesSlidingHandle) {
                                                _draggedHandleKey = 'center2';
                                              }
                                            }
                                          }

                                          if (touchesSlidingHandle) {
                                            _isDraggingHandle = true;
                                            hitHandle = true;
                                          }
                                        }

                                        if (hitHandle) {
                                          // Done, drag started for the handle
                                        } else {
                                          final dividerX =
                                              bounds.left +
                                              bounds.width *
                                                  _visualDoubleSashRatio(zone);
                                          final dividerTop = _modelToScreen(
                                            Offset(dividerX, bounds.top),
                                          );
                                          final dividerBottom = _modelToScreen(
                                            Offset(dividerX, bounds.bottom),
                                          );
                                          final dividerScreenX = dividerTop.dx;
                                          final topScreenY = dividerTop.dy;
                                          final bottomScreenY =
                                              dividerBottom.dy;
                                          final double dist =
                                              (touchScreen.dx - dividerScreenX)
                                                  .abs();

                                          final double hitThreshold =
                                              (zone.content ==
                                                      ZoneContent.doubleSash &&
                                                  widget.model.activeSubZone ==
                                                      'all')
                                              ? 60.0
                                              : 30.0;
                                          if (zone.content ==
                                                  ZoneContent.doubleSash &&
                                              dist < hitThreshold &&
                                              touchScreen.dy >=
                                                  topScreenY - 20.0 &&
                                              touchScreen.dy <=
                                                  bottomScreenY + 20.0) {
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
                                                    widget
                                                        .model
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
                                                  final leftGlassR = widget
                                                      .model
                                                      .getSafeGlassRect(
                                                        leftR,
                                                        sashT,
                                                      );
                                                  final rightGlassR = widget
                                                      .model
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
                                                    .getSafeGlassRect(
                                                      leftR,
                                                      sashT,
                                                    );
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
                                          } else if (_rightMouseDown) {
                                            // A right-button drag that grabs
                                            // nothing moves the view.
                                            _isPanningCanvas = true;
                                          } else {
                                            // Defer drawing start — wait for real drag in onScaleUpdate
                                            // (left button only).
                                            widget.model.pendingDrawStart =
                                                modelPos;
                                          }
                                        }
                                      } else if (_rightMouseDown) {
                                        _isPanningCanvas = true;
                                      } else if (widget.model.isDrawingMode &&
                                          widget.model.selection.type !=
                                              SelectionType.mullion) {
                                        widget.model.pendingDrawStart =
                                            modelPos;
                                      }
                                    }
                                  },
                                  onScaleUpdate: (details) {
                                    // The pointer listener pans the view.
                                    if (_isMiddlePanning) return;
                                    final notchCorner = _draggedNotchCorner;
                                    if (notchCorner != null) {
                                      _updateCornerNotchDrag(
                                        notchCorner,
                                        details.localFocalPoint,
                                      );
                                      return;
                                    }
                                    final slantEnd = _draggedSlantEnd;
                                    if (slantEnd != null) {
                                      widget.model.previewSlantedDividerEnd(
                                        slantEnd.zoneId,
                                        slantEnd.dividerId,
                                        atStart: slantEnd.atStart,
                                        pointer: _getModelPos(
                                          details.localFocalPoint,
                                        ),
                                      );
                                      return;
                                    }
                                    if (_isPanningCanvas) {
                                      setState(() {
                                        _userPan += details.focalPointDelta;
                                      });
                                      return;
                                    }
                                    final draggedBadge = _draggedAngleBadge;
                                    if (draggedBadge != null) {
                                      widget.model.dragAngleBadge(
                                        draggedBadge,
                                        details.focalPointDelta /
                                            (_userScale *
                                                widget.model.canvasScale),
                                      );
                                      return;
                                    }
                                    final draggedDimension = _draggedDimension;
                                    if (draggedDimension != null) {
                                      final delta =
                                          details.focalPointDelta /
                                          (_userScale *
                                              widget.model.canvasScale);
                                      widget.model.dragDimension(
                                        draggedDimension.dragKey,
                                        delta.dx * draggedDimension.normal.dx +
                                            delta.dy *
                                                draggedDimension.normal.dy,
                                      );
                                      return;
                                    }
                                    if (_draggedHingeEdge != null &&
                                        details.pointerCount < 2) {
                                      _dragHingeTo(details.localFocalPoint);
                                      return;
                                    }
                                    if (details.pointerCount >= 2) {
                                      setState(() {
                                        double newScale =
                                            (_baseUserScale * details.scale)
                                                .clamp(0.5, 5.0);
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
                                      final isPropertyDrag =
                                          _isDraggingSlantLeft ||
                                          _isDraggingSlantRight ||
                                          _isDraggingArch ||
                                          _isDraggingDoubleSashDivider ||
                                          _isDraggingSashDivision ||
                                          _isDraggingDecor ||
                                          _isDraggingHinge ||
                                          _isDraggingHandle ||
                                          widget.model.selection.type ==
                                              SelectionType.mullion ||
                                          widget.model.selection.type ==
                                              SelectionType.innerDivision;
                                      if (isPropertyDrag &&
                                          !_propertyDragHistorySaved) {
                                        widget.model.saveSnapshotOutside();
                                        _propertyDragHistorySaved = true;
                                      }
                                      final modelPos = _getModelPos(
                                        details.localFocalPoint,
                                      );
                                      // Commit pendingDrawStart → real drawing only after
                                      // the finger has actually moved (≥5 logical pixels)
                                      if (widget.model.drawingStart == null &&
                                          !_rightMouseDown &&
                                          widget.model.pendingDrawStart !=
                                              null) {
                                        final pending =
                                            widget.model.pendingDrawStart!;
                                        final screenPending = _modelToScreen(
                                          pending,
                                        );
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
                                          _draggedFrameZoneId != null) {
                                        final handle =
                                            _draggedFrameResizeHandle!;
                                        final moveLeft =
                                            handle == _FrameResizeHandle.left ||
                                            handle ==
                                                _FrameResizeHandle.topLeft ||
                                            handle ==
                                                _FrameResizeHandle.bottomLeft;
                                        final moveRight =
                                            handle ==
                                                _FrameResizeHandle.right ||
                                            handle ==
                                                _FrameResizeHandle.topRight ||
                                            handle ==
                                                _FrameResizeHandle.bottomRight;
                                        final moveTop =
                                            handle == _FrameResizeHandle.top ||
                                            handle ==
                                                _FrameResizeHandle.topLeft ||
                                            handle ==
                                                _FrameResizeHandle.topRight;
                                        final moveBottom =
                                            handle ==
                                                _FrameResizeHandle.bottom ||
                                            handle ==
                                                _FrameResizeHandle.bottomLeft ||
                                            handle ==
                                                _FrameResizeHandle.bottomRight;

                                        // A click on a handle that moves a
                                        // pixel or two is a click (a second
                                        // one shows the shape circles), not
                                        // a resize.
                                        var moved = details.focalPointDelta;
                                        if (!_frameResizeHistorySaved) {
                                          moved =
                                              details.localFocalPoint -
                                              _focalPointStart;
                                          if (moved.distance <=
                                              _mouseClickSlop) {
                                            return;
                                          }
                                        }
                                        final scaleFactor =
                                            _userScale *
                                            widget.model.canvasScale;
                                        final deltaX =
                                            (moveLeft || moveRight) &&
                                                scaleFactor > 0.0001
                                            ? moved.dx / scaleFactor
                                            : 0.0;
                                        final deltaY =
                                            (moveTop || moveBottom) &&
                                                scaleFactor > 0.0001
                                            ? moved.dy / scaleFactor
                                            : 0.0;
                                        widget.model.resizeFrameFromHandles(
                                          _draggedFrameZoneId!,
                                          moveLeft: moveLeft,
                                          moveRight: moveRight,
                                          moveTop: moveTop,
                                          moveBottom: moveBottom,
                                          deltaX: deltaX,
                                          deltaY: deltaY,
                                          saveHistory:
                                              !_frameResizeHistorySaved,
                                        );
                                        _frameResizeHistorySaved = true;
                                        final anchorShift =
                                            widget.model.lastResizeAnchorShift;
                                        if (anchorShift != Offset.zero) {
                                          widget.model.lastResizeAnchorShift =
                                              Offset.zero;
                                          setState(() {
                                            _userPan -=
                                                anchorShift *
                                                (_userScale *
                                                    widget.model.canvasScale);
                                          });
                                        }
                                      } else if (_isDraggingSlantLeft ||
                                          _isDraggingSlantRight ||
                                          _isDraggingArch) {
                                        // Only the dashed ghost follows the
                                        // pointer; the frame changes on
                                        // release (_commitShapeDragPreview).
                                        _updateShapeDragPreview(
                                            details.focalPointDelta.dy /
                                            (_userScale *
                                                  widget.model.canvasScale),
                                        );
                                      } else if (widget.model.selection.type ==
                                          SelectionType.mullion) {
                                        widget.model
                                            .moveSelectedMullionWithHistory(
                                              (widget
                                                          .model
                                                          .selection
                                                          .isHorizontalMullion!
                                                      ? details
                                                            .focalPointDelta
                                                            .dy
                                                      : details
                                                            .focalPointDelta
                                                            .dx) /
                                                  (_userScale *
                                                      widget.model.canvasScale),
                                              saveHistory: false,
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
                                          saveHistory: false,
                                        );
                                      } else if (_isDraggingDecor &&
                                          _draggedDecorZoneId != null &&
                                          widget.model.isDrawingMode) {
                                        final zone = widget.model.zones
                                            .firstWhere(
                                              (z) =>
                                                  z.id == _draggedDecorZoneId,
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
                                          _storedDoubleSashRatio(newRatio),
                                          saveHistory: false,
                                        );
                                      } else if (_isDraggingSashDivision &&
                                          _draggedSashZoneId != null &&
                                          widget.model.isDrawingMode) {
                                        final zone = widget.model.zones
                                            .firstWhere(
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
                                                saveHistory: false,
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
                                                saveHistory: false,
                                              );
                                        }
                                      } else if (!_suppressHandleDragForLongPress &&
                                          _isDraggingHandle &&
                                          widget.model.selectedZone != null &&
                                          (!(widget
                                                          .model
                                                          .selectedZone!
                                                          .content ==
                                                      ZoneContent.doubleSash &&
                                                  widget.model.activeSubZone ==
                                                      'all') ||
                                              (_pointerButtons &
                                                      kSecondaryMouseButton) !=
                                                  0) &&
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
                                    try {
                                    if (widget.model.drawingStart != null) {
                                      widget.model.endDrawing();
                                    }
                                    } catch (error, stack) {
                                      debugPrint('endDrawing failed: $error');
                                      debugPrintStack(stackTrace: stack);
                                    }
                                    final notice = widget.model.drawingNotice;
                                    widget.model.drawingNotice = null;
                                    if (notice != null) _showSlantNotice(notice);
                                    if (_draggedSlantEnd != null) {
                                      _draggedSlantEnd = null;
                                      final error = widget.model
                                          .commitSlantedDividerPreview();
                                      if (error != null) {
                                        _showSlantNotice(error);
                                      }
                                    }
                                    // A sub-5px drag never started drawing;
                                    // do not let it hijack the next drag.
                                    widget.model.pendingDrawStart = null;
                                    _isPanningCanvas = false;
                                    _isMiddlePanning = false;
                                    _draggedHandleKey = null;
                                    _draggedDimension = null;
                                    _draggedAngleBadge = null;
                                    _commitShapeDragPreview();
                                    _isDraggingHandle = false;
                                    _isDraggingHinge = false;
                                    if (_draggedHingeEdge != null) {
                                      // Show the hinge toolbar again.
                                      setState(() => _draggedHingeEdge = null);
                                    }
                                    _suppressHandleDragForLongPress = false;
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
                                    _propertyDragHistorySaved = false;
                                    if (_draggedNotchCorner != null) {
                                      _draggedNotchCorner = null;
                                      _commitCornerNotchDrag();
                                    }
                                    if (_notchModeFromRightDrag) {
                                      _notchModeFromRightDrag = false;
                                      widget.model.cornerNotchMode = false;
                                      widget.model.refreshUI();
                                    }
                                    // Refit and recentre after the drag.
                                    setState(
                                      () => widget.model.holdCamera = false,
                                    );
                                  },
                                  child: Listener(
                                    onPointerSignal:
                                        _handleDrawingPointerSignal,
                                    onPointerDown: (event) {
                                      _pointerButtons = event.buttons;
                                      _mouseClickStart =
                                          event.kind ==
                                                  PointerDeviceKind.mouse &&
                                              event.buttons ==
                                                  kPrimaryMouseButton
                                          ? (
                                              position: event.localPosition,
                                              time: event.timeStamp,
                                            )
                                          : null;
                                    },
                                    onPointerCancel: (_) {
                                      _mouseClickStart = null;
                                      widget.model.holdCamera = false;
                                    },
                                    onPointerUp: (event) {
                                      _lastPointerUpTime = event.timeStamp;
                                      final start = _mouseClickStart;
                                      _mouseClickStart = null;
                                      if (start == null ||
                                          event.timeStamp - start.time >=
                                              kLongPressTimeout) {
                                        return;
                                      }
                                      final details = TapUpDetails(
                                        kind: PointerDeviceKind.mouse,
                                        globalPosition: event.position,
                                        localPosition: start.position,
                                      );
                                      // After the gesture recognizers have
                                      // seen the release (a drag ends first).
                                      scheduleMicrotask(() {
                                        if (mounted) handleCanvasTap(details);
                                      });
                                    },
                                    onPointerMove: (event) {
                                      final start = _mouseClickStart;
                                      if (start != null &&
                                          (event.localPosition -
                                                      start.position)
                                                  .distance >
                                              _mouseClickSlop) {
                                        _mouseClickStart = null;
                                      }
                                      if (event.kind ==
                                              PointerDeviceKind.mouse &&
                                          (event.buttons &
                                                  kMiddleMouseButton) !=
                                              0) {
                                        setState(() {
                                          _userPan += event.delta;
                                        });
                                      }
                                    },
                                    child: MouseRegion(
                                      cursor: _isWindowsDesktop
                                          ? SystemMouseCursors.precise
                                          : MouseCursor.defer,
                                      child: Container(
                                        width: double.infinity,
                                        height: double.infinity,
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? const Color(0xFF232332)
                                              : const Color(0xFFF5F5F5),
                                        ),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            RepaintBoundary(
                                              child: CustomPaint(
                                                size: Size(
                                                  constraints.maxWidth,
                                                  constraints.maxHeight,
                                                ),
                                                painter: AppWorkspacePainter(
                                                  model: widget.model,
                                                  userScale: _userScale,
                                                  userPan: _userPan,
                                                  isDarkMode:
                                                      Theme.of(context)
                                                          .brightness ==
                                                      Brightness.dark,
                                                ),
                                              ),
                                            ),
                                            IgnorePointer(
                                              child: CustomPaint(
                                                painter:
                                                    WorkspaceSelectionPainter(
                                                      model: widget.model,
                                                      userScale: _userScale,
                                                      userPan: _userPan,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Follows the model (and the painted hinge
                                // positions) without rebuilding the screen.
                                Positioned.fill(
                                  child: ListenableBuilder(
                                    listenable: Listenable.merge([
                                      widget.model,
                                      widget.model.drawingRepaint,
                                    ]),
                                    builder: (context, _) => Stack(
                                      children: [
                                        ?_buildHingeToolbar(constraints),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_isWindowsDesktop)
                                  Positioned(
                                    top: 18,
                                    right: _paintbrushSecondsLeft > 0
                                        ? 150
                                        : 18,
                                    child: Offstage(
                                      offstage: true,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).cardColor.withValues(alpha: 0.94),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Theme.of(context)
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
                                                          constraints.maxWidth /
                                                              2,
                                                          constraints
                                                                  .maxHeight /
                                                              2,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              Container(
                                                width: 26,
                                                height: 1,
                                                color: Theme.of(
                                                  context,
                                                ).dividerColor,
                                              ),
                                              Semantics(
                                                button: true,
                                                label: 'تصغير الرسم',
                                                child: IconButton(
                                                  icon: const Icon(
                                                    Icons.remove,
                                                  ),
                                                  onPressed: () =>
                                                      _changeDrawingZoom(
                                                        1 / _zoomStep,
                                                        Offset(
                                                          constraints.maxWidth /
                                                              2,
                                                          constraints
                                                                  .maxHeight /
                                                              2,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              Container(
                                                width: 26,
                                                height: 1,
                                                color: Theme.of(
                                                  context,
                                                ).dividerColor,
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
                                              if (widget
                                                      .model
                                                      .usesProfileAngle &&
                                                  widget
                                                      .model
                                                      .activeProfileAngleJunctions
                                                      .isNotEmpty) ...[
                                                Container(
                                                  width: 26,
                                                  height: 1,
                                                  color: Theme.of(
                                                    context,
                                                  ).dividerColor,
                                                ),
                                                Semantics(
                                                  button: true,
                                                  label:
                                                      widget
                                                          .model
                                                          .viewAs90DegreeCorner
                                                      ? 'منظور 90°'
                                                      : 'مسقط مسطح 2D',
                                                  child: IconButton(
                                                    tooltip:
                                                        widget
                                                            .model
                                                            .viewAs90DegreeCorner
                                                        ? Localization.translate(
                                                            'التبديل إلى المسقط المسطح 2D',
                                                            lang,
                                                          )
                                                        : Localization.translate(
                                                            'التبديل إلى منظور الزاوية 90° (3D)',
                                                            lang,
                                                          ),
                                                    icon: Icon(
                                                      widget
                                                              .model
                                                              .viewAs90DegreeCorner
                                                          ? Icons
                                                                .view_in_ar_rounded
                                                          : Icons
                                                                .crop_square_rounded,
                                                      color:
                                                          widget
                                                              .model
                                                              .viewAs90DegreeCorner
                                                          ? Colors.blue
                                                          : null,
                                                    ),
                                                    onPressed: () {
                                                      setState(() {
                                                        widget.model
                                                            .toggle90DegreeCornerView();
                                                      });
                                                    },
                                                  ),
                                                ),
                                              ],
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
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
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
                                              '$_paintbrushSecondsLeft ${_tr('ث')}',
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
                                if (_isWindowsDesktop &&
                                    !_hidePresetCard &&
                                    widget.model.zones.isEmpty &&
                                    !widget.model.isShutterOnly &&
                                    widget.model.drawingStart == null)
                                  PositionedDirectional(
                                    top: 16,
                                    end: 16,
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxWidth: 270,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).cardColor.withValues(alpha: 0.96),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).dividerColor.withValues(alpha: 0.6),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.15,
                                            ),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              _PresetThumbnailWidget(
                                                preset: WindowPresetType
                                                    .slidingNoShutter,
                                                width: 32,
                                                height: 32,
                                                isDark:
                                                    Theme.of(
                                                      context,
                                                    ).brightness ==
                                                    Brightness.dark,
                                                accentColor:
                                                    Colors.blue.shade700,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  Localization.translate(
                                                    'أنظمة ونماذج جاهزة للرسم السريع',
                                                    lang,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () =>
                                                    _setHidePresetCard(true),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  child: Icon(
                                                    Icons.close_rounded,
                                                    size: 18,
                                                    color: Theme.of(
                                                      context,
                                                    ).hintColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            Localization.translate(
                                              'أدخل أبعاد الإطار واختر النموذج المطلوب ليرسم تلقائياً بدقة',
                                              lang,
                                            ),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white60
                                                  : Colors.black54,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 10),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.blue.shade700,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () =>
                                                _showPresetSystemsDialog(
                                                  context,
                                                ),
                                            icon: const Icon(
                                              Icons.touch_app_rounded,
                                              size: 16,
                                            ),
                                            label: Text(
                                              Localization.translate(
                                                'اختيار نظام جاهز',
                                                lang,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (activeTopToolbar != null)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: activeTopToolbar,
                                  ),
                                if (_isWindowsDesktop)
                                  AnimatedPositioned(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    top:
                                        (activeTopToolbar != null)
                                        ? 62
                                        : 14,
                                    left: _isLeftDrawerOpen ? 342 : 12,
                                    // The drawing area already ends at the
                                    // bottom menu: the bar runs down to it
                                    // and scrolls only when it is too long
                                    // (clear of the button that raises a
                                    // hidden bottom menu).
                                    bottom: _isBottomPanelExpanded ? 12 : 56,
                                    child: _buildQuickActionsBar(
                                      context,
                                      isVertical: true,
                                    ),
                                  )
                                else
                                  Positioned(
                                    top:
                                        (activeTopToolbar != null)
                                        ? 58
                                        : 12,
                                    left: 12,
                                    right: 12,
                                    child: Align(
                                      alignment: AlignmentDirectional.topStart,
                                      child: _buildQuickActionsBar(
                                        context,
                                        isVertical: false,
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

                  // 🔵 زر رفع القائمة السفلية عند إخفائها
                  if (!_isBottomPanelExpanded)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _isBottomPanelExpanded = true),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade700,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),

                  // 🟢 القائمة الجانبية اليسرى (Left Drawer) لخصائص الزجاج
                  if (!widget.model.isShutterOnly)
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
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
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
                          if (!_isWindowsDesktop)
                          GestureDetector(
                            onTap: () {
                              if (!_isLeftDrawerOpen)
                                widget.model.clearSelection();
                              setState(
                                () => _isLeftDrawerOpen = !_isLeftDrawerOpen,
                              );
                            },
                            onVerticalDragUpdate: (details) {
                              setState(() {
                                _leftDrawerHandleTop += details.delta.dy;
                                if (_leftDrawerHandleTop < 0) {
                                  _leftDrawerHandleTop = 0;
                                }
                                double maxTop =
                                    MediaQuery.of(context).size.height -
                                    120 -
                                    _drawerHandleHeight -
                                    15;
                                if (_leftDrawerHandleTop > maxTop) {
                                  _leftDrawerHandleTop = maxTop;
                                }
                              });
                            },
                            child: Container(
                              margin: EdgeInsets.only(
                                top: _leftDrawerHandleTop,
                              ),
                              width: _drawerHandleWidth,
                              height: _drawerHandleHeight,
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
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
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.blue.shade300
                                    : Colors.blue.shade800,
                                size: 20,
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
                        if (!_isWindowsDesktop)
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
                                  MediaQuery.of(context).size.height -
                                  120 -
                                  _drawerHandleHeight -
                                  15;
                              if (_rightDrawerHandleTop > maxTop) {
                                _rightDrawerHandleTop = maxTop;
                              }
                            });
                          },
                          child: Container(
                            margin: EdgeInsets.only(top: _rightDrawerHandleTop),
                            // 🟢 إزاحة بسيطة للزر ليكون شكله أنيقاً
                            width: _drawerHandleWidth,
                            height: _drawerHandleHeight,
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
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
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.blue.shade300
                                  : Colors.blue.shade800,
                              size: 20,
                            ),
                          ),
                        ),
                        Container(
                          width: 330,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
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
              );
                },
              ),
      ),
    );
  }

  Future<void> _confirmExitFromDrawing() async {
    if (_isExitDialogOpen || !mounted) return;
    _isExitDialogOpen = true;
    try {
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(Localization.translate('تأكيد الخروج', lang)),
          content: Text(
            Localization.translate('هل تريد الخروج من صفحة الرسم؟', lang),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(Localization.translate('خروج', lang)),
            ),
          ],
        ),
      );
      if (shouldExit == true && mounted) {
        Navigator.of(
          context,
        ).pop(widget.model.hasDrawnGeometry ? widget.model : null);
      }
    } finally {
      _isExitDialogOpen = false;
    }
  }



  /// Uses the exact same formula as [WindowPainter] for the number written
  /// inside a sash profile.  The dialog therefore never opens with a value
  /// that differs by the PVC welding loss or by the series overlap.
  double _openingSashOverlapForDrawing() => widget.model.openingSashOverlap;

  /// A slant corner or the arch dragged back within this distance of the
  /// straight head snaps onto it (magnetic return).
  static const double _shapeSnapMm = 50.0;
  double? _shapeRawLeft;
  double? _shapeRawRight;
  double? _shapeRawArch;

  /// Moves the dashed ghost of the head. The raw pointer values are kept
  /// separately so the magnet does not make the handle sticky.
  void _updateShapeDragPreview(double dy) {
    final model = widget.model;
    if (_isDraggingSlantLeft) {
      _shapeRawLeft = (_shapeRawLeft ?? model.topSlantLeftY) + dy;
    } else if (_isDraggingSlantRight) {
      _shapeRawRight = (_shapeRawRight ?? model.topSlantRightY) + dy;
    } else if (_isDraggingArch) {
      // The handle sits on the apex, which moves one-to-one with the rise.
      _shapeRawArch = (_shapeRawArch ?? model.archHeight) - dy;
    }
    double snap(double value) => value.abs() < _shapeSnapMm ? 0.0 : value;
    model.setTopShapePreview(
      model.clampTopShape(
        leftSlant: _shapeRawLeft == null ? null : snap(_shapeRawLeft!),
        rightSlant: _shapeRawRight == null ? null : snap(_shapeRawRight!),
        arch: _shapeRawArch == null ? null : snap(_shapeRawArch!),
      ),
    );
  }

  /// Applies the ghost to the frame as one undo step.
  void _commitShapeDragPreview() {
    final preview = widget.model.topShapePreview;
    _shapeRawLeft = null;
    _shapeRawRight = null;
    _shapeRawArch = null;
    if (preview == null) return;
    widget.model.setTopShapePreview(null);
    widget.model.updateTopSlantAndArch(
      leftSlant: preview.left,
      rightSlant: preview.right,
      arch: preview.arch,
    );
  }

  /// WindowPainter mirrors the double-sash divider in the external view, so
  /// hit tests, drags and editors must work with the ratio as it is seen.
  double _visualDoubleSashRatio(WindowZone zone) => widget.model.isInternalView
      ? zone.doubleSashRatio
      : 1.0 - zone.doubleSashRatio;

  double _storedDoubleSashRatio(double visualRatio) =>
      widget.model.isInternalView ? visualRatio : 1.0 - visualRatio;

  /// Inverse of [_shownDoubleSashCuttingWidth]: the visual left-leaf ratio
  /// that makes the drawn cutting size equal [leftCut].
  double _visualRatioForLeftLeafCut(WindowZone zone, double leftCut) {
    final weldLoss = widget.model.isPVC ? 5.0 : 0.0;
    final totalCutWidth =
        zone.boundary.width + _openingSashOverlapForDrawing() * 2;
    return (leftCut + weldLoss) / totalCutWidth;
  }

  /// Edits a jamb height or the arch rise of a slanted/arched head. A jamb
  /// may rise above the overall height (up to one bar length) or drop until
  /// the frame or a top zone reaches its minimum; the arch rises from zero to
  /// a semicircle.
  /// Tap on the handle-height number: type the height of the handle above
  /// the sash bottom.
  void _showHandleHeightDialog(String zoneId) {
    final model = widget.model;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final label = model.drawnHandleHeightLabels[zoneId];
    final current = model.handleHeightFromBottom(zoneId);
    if (label == null || current == null) return;
    final span = label.sashBottom - label.sashTop;
    final title = Localization.translate('ارتفاع المقبض', lang);
    final ctrl = TextEditingController(text: current.round().toString());

    void apply(BuildContext dialogContext) {
      final value = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (!_acceptDimension(value, 1, span - 1)) return;
      model.setHandleHeightFromBottom(zoneId, value!);
      Navigator.pop(dialogContext);
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => apply(dialogContext),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: '$title (mm)',
            helperText: Localization.translate(
              'handle_height_from_sash_bottom',
              lang,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          ElevatedButton(
            onPressed: () => apply(dialogContext),
            child: Text(Localization.translate('تطبيق', lang)),
          ),
        ],
      ),
    );
  }

  void _showHeadDimensionDialog(String key) {
    final model = widget.model;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final bool isArch = key == 'archRise';
    final bool isLeft = key == 'leftJamb';
    final double bottomSlant = isLeft
        ? model.bottomSlantLeftY
        : model.bottomSlantRightY;
    final double base = model.height - bottomSlant;
    final double maxRaise = math.max(
      0.0,
      model.maximumFrameBarLengthMm - model.height,
    );
    final double current = isArch
        ? model.archHeight
        : base - (isLeft ? model.topSlantLeftY : model.topSlantRightY);
    final double minValue = isArch
        ? 0.0
        : base - model.maxTopSlantMm(left: isLeft);
    final double maxValue = isArch ? model.width / 2 : base + maxRaise;
    final String title = isArch
        ? 'ذروة القوس (mm)'
        : (isLeft ? 'ارتفاع القائم الأيسر (mm)' : 'ارتفاع القائم الأيمن (mm)');
    final ctrl = TextEditingController(text: current.round().toString());

    void apply(BuildContext dialogContext) {
      final value = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (!_acceptDimension(value, minValue, maxValue)) return;
      if (isArch) {
        model.updateTopSlantAndArch(arch: value);
      } else if (isLeft) {
        model.updateTopSlantAndArch(leftSlant: base - value!);
      } else {
        model.updateTopSlantAndArch(rightSlant: base - value!);
      }
      Navigator.pop(dialogContext);
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            Localization.translate(title, lang),
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
            onSubmitted: (_) => apply(dialogContext),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: Localization.translate(title, lang),
              helperText: '${minValue.ceil()} – ${maxValue.floor()} mm',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () => apply(dialogContext),
              child: Text(
                Localization.translate('تطبيق', lang),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Shows a slanted-division rule (SlantedDivisionError key) to the user.
  void _showSlantNotice(String key) {
    final min = key == SlantedDivisionError.angleTooSharp
        ? SlantedDivisionGeometry.minimumAngleDeg.round().toString()
        : key == WindowModel.zoneTooSmallKey
        ? WindowModel.minimumZoneMm.round().toString()
        : WindowModel.minimumSashCellMm.round().toString();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_tr(key).replaceAll('{min}', min)),
        backgroundColor: Colors.orange.shade800,
      ),
    );
  }

  /// End handle of the selected slanted mullion under a screen point.
  ({String zoneId, String dividerId, bool atStart})? _slantEndAt(
    Offset screenPoint,
  ) {
    final selected = widget.model.selectedSlantedDivider;
    if (selected == null) return null;
    WindowZone? zone;
    for (final z in widget.model.zones) {
      if (z.id == selected.zoneId) zone = z;
    }
    final divider = widget.model.slantedDividerById(
      selected.zoneId,
      selected.dividerId,
    );
    if (zone == null || divider == null) return null;
    final (a, b) = widget.model.slantedGeometryFor(zone).centreLine(divider);
    for (final (point, atStart) in [(a, true), (b, false)]) {
      if ((_modelToScreen(point) - screenPoint).distance <= 18.0) {
        return (
          zoneId: selected.zoneId,
          dividerId: selected.dividerId,
          atStart: atStart,
        );
      }
    }
    return null;
  }

  /// Editor of one slanted mullion: each end as a distance from the outer
  /// frame edge (left edge for top/bottom ends, top edge for side ends),
  /// the angles shown on the drawing and the halved saw angles, the bar's
  /// long-point length, and delete.
  void _showSlantedDividerDialog(({String zoneId, String dividerId}) hit) {
    final model = widget.model;
    WindowZone? zone;
    for (final z in model.zones) {
      if (z.id == hit.zoneId) zone = z;
    }
    final divider = model.slantedDividerById(hit.zoneId, hit.dividerId);
    if (zone == null || divider == null) return;
    final z = zone;
    final r = z.boundary;
    final geometry = model.slantedGeometryFor(z);
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String t(String key) => Localization.translate(key, lang);

    bool horizontal(ZoneEdge e) => e == ZoneEdge.top || e == ZoneEdge.bottom;
    double absolute(SlantedDividerAnchor a) => horizontal(a.edge)
        ? r.left + a.ratio * r.width
        : r.top + a.ratio * r.height;
    String edgeName(ZoneEdge e) => t(switch (e) {
      ZoneEdge.top => 'الضلع العلوي',
      ZoneEdge.bottom => 'الضلع السفلي',
      ZoneEdge.left => 'الضلع الأيسر',
      ZoneEdge.right => 'الضلع الأيمن',
    });
    String fieldLabel(ZoneEdge e) =>
        '${edgeName(e)} — ${t(horizontal(e) ? 'المسافة من يسار الإطار (mm)' : 'المسافة من أعلى الإطار (mm)')}';

    final startCtrl = TextEditingController(
      text: absolute(divider.start).toStringAsFixed(1),
    );
    final endCtrl = TextEditingController(
      text: absolute(divider.end).toStringAsFixed(1),
    );
    String angles(bool atStart) {
      final a = geometry.angleWithEdgeDeg(divider, atStart: atStart);
      final cut = geometry.cutAngleDeg(divider, atStart: atStart);
      return '${t('الزاوية')}: ${a.toStringAsFixed(2)}° · '
          '${t('زاوية القص')}: ${cut.toStringAsFixed(2)}°';
    }

    SlantedDividerAnchor? anchorFrom(
      SlantedDividerAnchor old,
      String text,
    ) {
      final value = double.tryParse(text.replaceAll(',', '.'));
      if (value == null) return null;
      final start = horizontal(old.edge) ? r.left : r.top;
      final length = horizontal(old.edge) ? r.width : r.height;
      final ratio = (value - start) / length;
      if (ratio < 0 || ratio > 1) return null;
      return SlantedDividerAnchor(old.edge, ratio);
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        void apply() {
          final start = anchorFrom(divider.start, startCtrl.text);
          final end = anchorFrom(divider.end, endCtrl.text);
          if (start == null || end == null) {
            _acceptDimension(null, 0, 0);
            return;
          }
          final error = model.setSlantedDivider(
            hit.zoneId,
            divider.copyWith(start: start, end: end),
          );
          if (error != null) {
            _showSlantNotice(error);
            return;
          }
          Navigator.pop(dialogContext);
        }

        Widget field(TextEditingController ctrl, String label) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            onSubmitted: (_) => apply(),
            decoration: InputDecoration(labelText: label),
          ),
        );

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(t('تقسيم مائل')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field(startCtrl, fieldLabel(divider.start.edge)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(angles(true), style: const TextStyle(fontSize: 12)),
                ),
                field(endCtrl, fieldLabel(divider.end.edge)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(angles(false), style: const TextStyle(fontSize: 12)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${t('طول القص')}: '
                    '${geometry.cutLengthMm(divider).toStringAsFixed(1)} mm',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                model.removeSlantedDivider(hit.zoneId, hit.dividerId);
                Navigator.pop(dialogContext);
              },
              child: Text(t('حذف'), style: const TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                t('إلغاء'),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: apply,
              child: Text(t('تطبيق')),
            ),
          ],
        );
      },
    );
  }

  /// Rejects a typed size outside [min]–[max] with a translated message
  /// instead of silently ignoring or clamping it.
  bool _acceptDimension(double? value, double min, double max) {
    if (value != null && value >= min - 0.5 && value <= max + 0.5) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value == null || !min.isFinite || !max.isFinite
              ? _tr('يرجى إدخال قياس صحيح بالمليمتر')
              : _tr('القياس المسموح به بين {min} و {max} مم')
                    .replaceAll('{min}', min.ceil().toString())
                    .replaceAll('{max}', max.floor().toString()),
        ),
        backgroundColor: Colors.red,
      ),
    );
    return false;
  }

  /// Tells the user when a frame touching the corner profile cannot stand
  /// next to it (an integrated cover, or in aluminium a frame accepting a
  /// cover) and the series has no frame that can.
  void _warnProfileAngleFrames() {
    // A refused switch names the frames without a corner frame set; an
    // older drawing may also hold a corner profile with such a frame.
    final refused = widget.model.lastCornerPairingRefusal;
    widget.model.lastCornerPairingRefusal = const [];
    final problems = refused.isNotEmpty
        ? refused
        : widget.model.profileAngleFrameProblems;
    if (problems.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
          content: Text(
            _tr(
              'لا يمكن تفعيل بروفيل الزاوية: حدّد «إطار جهة بروفيل الزاوية» لـ {frames} في صفحة «ربط الإطارات».',
            ).replaceAll('{frames}', problems.join('، ')),
          ),
        ),
      );
  }

  double _shownDoubleSashCuttingWidth(WindowZone zone, double ratio) {
    final weldLoss = widget.model.isPVC ? 5.0 : 0.0;
    final totalCutWidth =
        zone.boundary.width + _openingSashOverlapForDrawing() * 2;
    return totalCutWidth * ratio - weldLoss;
  }





























  String _getColorName(GlassColor c) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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


  String _getDirectionName(OpenDirection d) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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























}

/// A horizontal scroll area with its own controller so the application-wide
/// Windows scroll behavior can expose and operate its horizontal scrollbar.
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
      child: widget.builder(context, _controller),
    );
  }
}

class _IntercallButton extends StatelessWidget {
  final int thickness;
  final bool selected;
  final VoidCallback onPressed;
  final bool showWarning;
  final bool exceedsCapacity;

  const _IntercallButton({
    required this.thickness,
    required this.selected,
    required this.onPressed,
    this.showWarning = false,
    this.exceedsCapacity = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              : exceedsCapacity
              ? (isDark
                    ? Colors.red.shade900.withValues(alpha: 0.15)
                    : Colors.red.shade50)
              : (isDark ? const Color(0xFF2E2E3E) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.blue
                : exceedsCapacity
                ? (isDark ? Colors.red.shade400 : Colors.red.shade300)
                : (isDark ? Colors.white24 : Colors.grey.shade300),
            width: selected ? 1.5 : (exceedsCapacity ? 1.2 : 1.0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Intercall',
              style: TextStyle(
                color: isDark
                    ? (exceedsCapacity ? Colors.red.shade300 : Colors.white)
                    : (selected
                          ? Colors.blue.shade900
                          : exceedsCapacity
                          ? Colors.red.shade700
                          : Colors.grey.shade800),
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
                      ? (exceedsCapacity ? Colors.red.shade400 : Colors.white)
                      : (selected
                            ? Colors.blue
                            : exceedsCapacity
                            ? Colors.red.shade400
                            : Colors.grey.shade500),
                ),
                Text(
                  thickness.toString(),
                  style: TextStyle(
                    color: isDark
                        ? Colors.white
                        : (selected
                              ? Colors.blue.shade700
                              : exceedsCapacity
                              ? Colors.red.shade900
                              : Colors.black87),
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
                    ? (exceedsCapacity ? Colors.red.shade300 : Colors.white)
                    : (selected
                          ? Colors.blue.shade900
                          : exceedsCapacity
                          ? Colors.red.shade700
                          : Colors.grey.shade800),
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (exceedsCapacity) ...[
              const SizedBox(width: 5),
              Icon(
                Icons.block_rounded,
                color: isDark ? Colors.red.shade400 : Colors.red.shade700,
                size: 15,
              ),
            ] else if (showWarning) ...[
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
  final bool enabled;
  final String? disabledHint;

  const _ShutterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final foreground = enabled
        ? (selected ? color : Colors.grey.shade600)
        : Colors.grey.shade400;
    final background = enabled
        ? (selected ? color.withOpacity(0.12) : Colors.grey.shade100)
        : Colors.grey.shade200;
    return Tooltip(
      message: enabled
          ? Localization.translate(label, lang)
          : Localization.translate(
              disabledHint ?? 'غير متاح لهذا المقاس',
              lang,
            ),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(
              color: enabled && selected ? color : Colors.grey.shade300,
              width: selected ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(height: 3),
              Text(
                Localization.translate(label, lang),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: enabled
                      ? (selected ? color : Colors.grey.shade700)
                      : Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
  final bool showSubmenuIndicator;
  final bool enabled;

  const _ContentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.showWarning = false,
    this.showSubmenuIndicator = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.45,
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
                Localization.translate(
                  label,
                  Provider.of<AppSettingsProvider>(
                    context,
                    listen: false,
                  ).language,
                ),
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
              if (showSubmenuIndicator) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: isDark
                      ? Colors.white70
                      : (selected
                            ? Colors.blue.shade900
                            : Colors.grey.shade600),
                ),
              ],
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
      ),
    );
  }
}

/// Lightweight editor overlay. Selection changes repaint only this layer;
/// profiles, glass, textures, decorations and dimensions stay cached below.
class WorkspaceSelectionPainter extends CustomPainter {
  final WindowModel model;
  final double userScale;
  final Offset userPan;

  /// Outlines the selected hinge and shows its centre distance from the
  /// start of the edge (bottom of the sash, or inside-left end).
  void _paintSelectedHinge(Canvas canvas, double scale) {
    final selected = model.selectedHinge;
    if (selected == null) return;
    final edge = model.hingeEdgeOf(selected.zoneId, selected.leaf);
    if (edge == null) return;
    WindowZone? zone;
    for (final z in model.zones) {
      if (z.id == edge.zoneId) zone = z;
    }
    if (zone == null) return;
    final positions = model.hingePositionsFor(zone, edge.leaf, edge.length);
    if (selected.index >= positions.length) return;
    final position = positions[selected.index];
    final center = edge.pointAt(position);
    final color = edge.editable ? Colors.blue.shade600 : Colors.grey.shade600;

    final rect = edge.vertical
        ? Rect.fromCenter(center: center, width: 16, height: 80)
        : Rect.fromCenter(center: center, width: 80, height: 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(6 / scale), Radius.circular(4 / scale)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 / scale,
    );

    // Dashed measuring line over the nearest span: to the next hinge or to
    // the end of the sash, whichever is closer, read from the bottom up.
    final gap = SashHingeRules.nearestGap(
      positions,
      selected.index,
      edge.length,
    );
    final dash = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.5 / scale;
    final step = 10 / scale;
    for (var d = gap.from; d < gap.to; d += step * 2) {
      canvas.drawLine(
        edge.pointAt(d),
        edge.pointAt(math.min(gap.to, d + step)),
        dash,
      );
    }
    for (final end in [gap.from, gap.to]) {
      // Small ticks at both ends of the measured span.
      final tick = edge.vertical
          ? Offset(8 / scale, 0)
          : Offset(0, 8 / scale);
      canvas.drawLine(edge.pointAt(end) - tick, edge.pointAt(end) + tick, dash);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: '${(gap.to - gap.from).round()}',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 / scale,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 4 / scale;
    final spanMid = edge.pointAt((gap.from + gap.to) / 2);
    final labelCenter = edge.vertical
        ? Offset(spanMid.dx + 8 / scale + tp.width / 2 + 16, spanMid.dy)
        : Offset(spanMid.dx, spanMid.dy - 8 / scale - tp.height / 2 - 16);
    final box = Rect.fromCenter(
      center: labelCenter,
      width: tp.width + pad * 2,
      height: tp.height + pad * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(4 / scale)),
      Paint()..color = color,
    );
    tp.paint(canvas, box.topLeft + Offset(pad, pad));
  }

  /// What a zone selection highlights: every sash after a long press, the
  /// leaf tapped in a sliding zone, the half tapped in a double sash, else
  /// the whole zone.
  List<Rect> _selectedSashRects(WindowZone zone) {
    if (model.allSashesSelected) {
      return [for (final z in model.selectedSashZones) z.boundary];
    }
    if (zone.content == ZoneContent.slidingSash) {
      final leaves = model.drawnSlidingLeafRects[zone.id];
      final index = model.selectedSlidingLeaf;
      if (leaves != null &&
          index != null &&
          index >= 0 &&
          index < leaves.length) {
        return [leaves[index]];
      }
    }
    final sub = model.activeSubZone;
    if (zone.content == ZoneContent.doubleSash &&
        sub != null &&
        sub != 'all' &&
        (sub.startsWith('left') || sub.startsWith('right'))) {
      final r = zone.boundary;
      // Same split as the drawing (mirrored in the inside view).
      final ratio = model.isInternalView
          ? zone.doubleSashRatio
          : 1.0 - zone.doubleSashRatio;
      final midX = r.left + r.width * ratio;
      return [
        sub.startsWith('left')
            ? Rect.fromLTRB(r.left, r.top, midX, r.bottom)
            : Rect.fromLTRB(midX, r.top, r.right, r.bottom),
      ];
    }
    return [zone.boundary];
  }

  WorkspaceSelectionPainter({
    required this.model,
    this.userScale = 1.0,
    this.userPan = Offset.zero,
    // drawingRepaint also carries the head-drag ghost, so the handles move
    // with it without a full model notification on every pointer event.
  }) : super(repaint: Listenable.merge([model, model.drawingRepaint]));

  @override
  void paint(Canvas canvas, Size size) {
    final scale = model.canvasScale * userScale;
    if (scale <= 0) return;
    canvas.save();
    canvas.translate(model.canvasDx + userPan.dx, model.canvasDy + userPan.dy);
    canvas.scale(scale);

    _paintSelectedHinge(canvas, scale);

    final selection = model.selection;
    final fill = Paint()
      ..color = Colors.green.shade600.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = Colors.green.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 / scale;

    if (selection.type == SelectionType.frame) {
      final key = selection.zoneId;
      final rect = key == null
          ? Rect.fromLTWH(0, 0, model.width, model.height)
          : model.frameRectForSelection(key);
      if (rect != null) {
        // Follow a slanted or arched head and a slanted bottom: the bounding
        // rectangle left the slanted part of the frame unselected.
        canvas.drawPath(model.frameSelectionPath(rect), outline);
      }
      if (rect != null && !model.frameShapeMode && !model.cornerNotchMode) {
        final side = 18.0 / scale;
        final handleFill = Paint()
          ..color = Colors.green.shade600
          ..style = PaintingStyle.fill;
        final handleBorder = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale;
        for (final center in <Offset>[
          rect.topLeft,
          Offset(rect.center.dx, rect.top),
          rect.topRight,
          Offset(rect.right, rect.center.dy),
          rect.bottomRight,
          Offset(rect.center.dx, rect.bottom),
          rect.bottomLeft,
          Offset(rect.left, rect.center.dy),
        ]) {
          if (_isCutFrameCorner(model, center)) continue;
          final handle = Rect.fromCenter(
            center: center,
            width: side,
            height: side,
          );
          canvas.drawRect(handle, handleFill);
          canvas.drawRect(handle, handleBorder);
        }
      }

      if (model.frameShapeMode && model.canShapeSelectedFrame) {
        final radius = 10.0 / scale;
        final amber = Paint()
          ..color = Colors.amber.shade800
          ..style = PaintingStyle.fill;
        final amberInner = Paint()
          ..color = Colors.amber.shade300
          ..style = PaintingStyle.fill;
        final whiteBorder = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / scale;
        void handle(Offset center) {
          canvas.drawCircle(center, radius, amber);
          canvas.drawCircle(center, radius * 0.45, amberInner);
          canvas.drawCircle(center, radius, whiteBorder);
        }

        // Handles follow the dashed ghost while a head drag is in progress.
        final shape =
            model.topShapePreview ??
            (
              left: model.topSlantLeftY,
              right: model.topSlantRightY,
              arch: model.archHeight,
            );
        handle(Offset(0, shape.left));
        handle(Offset(model.width, shape.right));
        // The arch handle sits on the apex (arc midpoint), where the hit
        // test in the gesture handler looks for it.
        handle(
          model.headArc(
                left: shape.left,
                right: shape.right,
                arch: shape.arch,
              )?.apex ??
          Offset(
            model.width / 2,
                (shape.left + shape.right) / 2,
          ),
        );
      }
    } else if (selection.type == SelectionType.zone ||
        selection.type == SelectionType.innerDivision) {
      final zoneId = selection.zoneId;
      WindowZone? zone;
      for (final candidate in model.zones) {
        if (candidate.id == zoneId) {
          zone = candidate;
          break;
        }
      }
      if (zone != null) {
        for (final rect in _selectedSashRects(zone)) {
          final shape = model.zoneSelectionPath(rect);
          canvas.drawPath(shape, fill);
          canvas.drawPath(shape, outline);
        }
      }
    } else if (selection.type == SelectionType.mullion &&
        selection.mullionPosition != null) {
      final horizontal = selection.isHorizontalMullion ?? false;
      final position = selection.mullionPosition!;
      final start = selection.mullionStart ?? 0.0;
      final end =
          selection.mullionEnd ?? (horizontal ? model.width : model.height);
      final thickness = math.max(8.0, model.mullionThickness);
      final rect = horizontal
          ? Rect.fromLTRB(
              start,
              position - thickness / 2,
              end,
              position + thickness / 2,
            )
          : Rect.fromLTRB(
              position - thickness / 2,
              start,
              position + thickness / 2,
              end,
            );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, outline);
    }

    // Selected slanted mullion: green outline and a handle on each end.
    final slanted = model.selectedSlantedDivider;
    if (slanted != null) {
      for (final zone in model.zones) {
        if (zone.id != slanted.zoneId) continue;
        final geometry = model.slantedGeometryFor(
          zone,
          dividers: model.slantedDividersShownFor(zone),
        );
        for (final d in geometry.dividers) {
          if (d.id != slanted.dividerId) continue;
          canvas.drawPath(Path()..addPolygon(geometry.band(d), true), outline);
          final (a, b) = geometry.centreLine(d);
          for (final end in [a, b]) {
            canvas.drawCircle(end, 9.0 / scale, Paint()..color = Colors.green.shade700);
            canvas.drawCircle(
              end,
              9.0 / scale,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.0 / scale,
            );
          }
        }
      }
    }

    _paintCornerNotchOverlay(canvas, model, scale);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WorkspaceSelectionPainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.userScale != userScale ||
        oldDelegate.userPan != userPan;
  }
}

/// Dashed ghost of the frame head while a slant/arch handle is dragged, with
/// the live jamb heights and arch rise. [scale] is the total canvas scale so
/// strokes and text keep a constant on-screen size.
void _paintTopShapePreview(
  Canvas canvas,
  WindowModel model,
  ({double left, double right, double arch}) shape,
  double scale,
) {
  final w = model.width;
  final h = model.height;
  final path = Path()
    ..moveTo(0, h - model.bottomSlantLeftY)
    ..lineTo(0, shape.left);
  final arc = model.headArc(
    left: shape.left,
    right: shape.right,
    arch: shape.arch,
  );
  if (arc != null) {
    path.arcToPoint(
      Offset(w, shape.right),
      radius: Radius.circular(arc.radius),
      clockwise: true,
    );
  } else {
    path.lineTo(w, shape.right);
  }
  path.lineTo(w, h - model.bottomSlantRightY);

  final stroke = Paint()
    ..color = const Color(0xFF1565C0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6 / scale;
  final dash = 10.0 / scale;
  final gap = 6.0 / scale;
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      canvas.drawPath(
        metric.extractPath(
          distance,
          math.min(distance + dash, metric.length),
        ),
        stroke,
      );
      distance += dash + gap;
    }
  }

  void label(double value, Offset anchor, Alignment align) {
    final painter = TextPainter(
      text: TextSpan(
        text: value.round().toString(),
        style: TextStyle(
          color: const Color(0xFF1565C0),
          fontSize: 15 / scale,
          fontWeight: FontWeight.w600,
          backgroundColor: Colors.white.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = Offset(
      anchor.dx - painter.width * (align.x + 1) / 2,
      anchor.dy - painter.height * (align.y + 1) / 2,
    );
    painter.paint(canvas, offset);
  }

  final pad = 14.0 / scale;
  label(
    h - model.bottomSlantLeftY - shape.left,
    Offset(-pad, shape.left),
    Alignment.centerRight,
  );
  label(
    h - model.bottomSlantRightY - shape.right,
    Offset(w + pad, shape.right),
    Alignment.centerLeft,
  );
  if (arc != null) {
    label(
      shape.arch,
      Offset(arc.apex.dx, arc.apex.dy - pad),
      Alignment.bottomCenter,
    );
  }
}

class AppWorkspacePainter extends CustomPainter {
  final WindowModel model;
  final double userScale;
  final Offset userPan;
  final bool isDarkMode;

  AppWorkspacePainter({
    required this.model,
    this.userScale = 1.0,
    this.userPan = Offset.zero,
    this.isDarkMode = false,
  }) : super(repaint: model.drawingRepaint);

  Color get _dimensionTextColor =>
      isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1F2937);

  Color get _dimensionLineColor =>
      isDarkMode ? const Color(0xFFCBD5E1) : Colors.blueGrey.shade700;

  Color get _dimensionWitnessColor => isDarkMode
      ? const Color(0xFF94A3B8).withValues(alpha: 0.9)
      : Colors.blueGrey.shade400.withValues(alpha: 0.6);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(model.canvasDx + userPan.dx, model.canvasDy + userPan.dy);
    canvas.scale(model.canvasScale * userScale);

    if (model.width > 0 &&
        model.height > 0 &&
        (model.zones.isNotEmpty || model.isShutterOnly)) {
      final painter = WindowPainter(
        model: model,
        showDrawingDimensions: true,
        showSelection: false,
        recordHitTargets: true,
      );
      painter.paint(canvas, size);
      // Keep the exterior dimensions outside the frame, then add compact
      // editable region labels and profile cut labels inside the drawing.
      model.dimensionLabelHits = [];
      _paintDimensions(canvas, model, Offset.zero);
      if (!model.isShutterOnly) {
        _paintZoneRegionDimensions(canvas, model);
        _paintDrawingProfileDimensions(canvas, model);
      }
      final shapePreview = model.topShapePreview;
      if (shapePreview != null) {
        _paintTopShapePreview(
          canvas,
          model,
          shapePreview,
          model.canvasScale * userScale,
        );
      }
    }

    if ((model.zones.isEmpty ||
            model.drawingMode == 'add_frame' ||
            model.drawingMode == 'shutter_only') &&
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
  void _paintZoneRegionDimensions(Canvas canvas, WindowModel model) {
    final innerWidth = model.width - model.profileThickness * 2;
    final innerHeight = model.height - model.profileThickness * 2;
    for (final zone in model.zones) {
      final r = zone.boundary;
      if (r.width < 55 || r.height < 55) continue;

      // Hide zone dimensions when sashes are added (show only for empty frame or fixed glass)
      final showZoneDimensions =
          zone.content == ZoneContent.empty ||
          zone.content == ZoneContent.fixedGlass;
      if (!showZoneDimensions) continue;

      final editableWidth = r.width < innerWidth - 2;
      final editableHeight = r.height < innerHeight - 2;
      final bottomInset = math.min(28.0, math.max(16.0, r.height * 0.18));
      final rightInset = math.min(28.0, math.max(16.0, r.width * 0.18));

      _paintZoneRegionLabel(
        canvas,
        '${r.width.toInt()} mm',
        Offset(r.center.dx, r.bottom - bottomInset),
        math.max(36.0, r.width - 18.0),
        editable: editableWidth,
      );
      _paintZoneRegionLabel(
        canvas,
        '${r.height.toInt()} mm',
        Offset(r.right - rightInset, r.center.dy),
        math.max(36.0, r.height - 18.0),
        vertical: true,
        editable: editableHeight,
      );
    }
  }

  void _paintZoneRegionLabel(
    Canvas canvas,
    String text,
    Offset center,
    double maxMainAxis, {
    bool vertical = false,
    required bool editable,
  }) {
    double fontSize = math.min(34.0, math.max(16.0, maxMainAxis * 0.18));
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: editable ? const Color(0xFF0F172A) : Colors.grey.shade700,
            fontSize: fontSize,
            fontWeight: FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width <= maxMainAxis || fontSize <= 10) break;
      fontSize -= 1.0;
    }
    if (painter.width > maxMainAxis + 1) return;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (vertical) canvas.rotate(-math.pi / 2);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  void _paintDrawingProfileDimensions(Canvas canvas, WindowModel model) {
    final frameThickness = model.profileThickness;
    if (frameThickness <= 0) return;

    final frameRects = model.getFrameRects();
    final frameSection = model.getSectionByType('frame');
    final slidingFrameSection = model.getSlidingSectionByType('frame');
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
    final integratedCoverWidth = model.integratedFrameSideCoverWidth;
    final hasIntegratedCover =
        model.isIntegratedFrame &&
        model.hasSideCovers &&
        model.isSideCoverAllowed &&
        integratedCoverWidth > 0;
    final hasSeparateCover =
        !model.isIntegratedFrame &&
        model.hasSideCovers &&
        model.canUseStandaloneSideCover;
    final separateCover = model.selectedSideCover;
    final separateCoverWidth = model.standaloneSideCoverWidth;
    final separateCoverThickness = model.standaloneSideCoverThickness;
    final hasSeparateCoverLeft =
        hasSeparateCover && model.isSideCoverSegmentEnabled('left');
    final hasSeparateCoverRight =
        hasSeparateCover && model.isSideCoverSegmentEnabled('right');
    final hasSeparateCoverTop =
        hasSeparateCover && model.isSideCoverSegmentEnabled('top');
    final hasSeparateCoverBottom =
        hasSeparateCover && model.isSideCoverSegmentEnabled('bottom');
    final minFrameLeft = frameRects.isEmpty
        ? 0.0
        : frameRects.map((rect) => rect.left).reduce(math.min);
    final maxFrameRight = frameRects.isEmpty
        ? 0.0
        : frameRects.map((rect) => rect.right).reduce(math.max);
    final minFrameTop = frameRects.isEmpty
        ? 0.0
        : frameRects.map((rect) => rect.top).reduce(math.min);
    final maxFrameBottom = frameRects.isEmpty
        ? 0.0
        : frameRects.map((rect) => rect.bottom).reduce(math.max);
    final frameCode = codeFrom(activeFrame, frameSection);
    final slidingFrameCode = codeFrom(
      model.slidingFrameOverride,
      slidingFrameSection,
    );
    final separateCoverCode = codeFrom(model.sideCoverOverride, separateCover);
    final weldAllowance = model.isFramePVC ? 5.0 : 0.0;

    // The labels inside profiles are cutting dimensions. Total exterior
    // dimensions remain outside the drawing and are deliberately untouched.
    // A standalone cover keeps its own cut dimensions, while its thickness
    // shortens the frame once at every side where the cover is installed.
    // An integrated cover belongs to the frame profile itself.
    if (!hasIntegratedCover) {
      for (final frame in frameRects) {
        final frameSectionForLabel = model.frameSectionForRect(frame);
        final effectiveFrameCode =
            (frameSectionForLabel?.code ?? '').trim().isNotEmpty
            ? frameSectionForLabel!.code.trim()
            : (model.frameUsesSlidingSeries(frame) &&
                      slidingFrameCode.isNotEmpty
                  ? slidingFrameCode
                  : frameCode);
        String sideFrameCode(String side) {
          final override = model.frameSideOverrideForRect(frame, side);
          final code = (override?['code'] ?? '').toString().trim();
          return code.isNotEmpty ? code : effectiveFrameCode;
        }

        final isOnlyFrame = frameRects.length == 1;
        final netHeight = model.hasShutter && !model.isCaissonTunnel
            ? model.height - model.shutterBoxHeight
            : model.height;
        final frameWidth =
            (isOnlyFrame ? model.width : frame.width) +
            weldAllowance -
            (hasSeparateCoverLeft &&
                    (isOnlyFrame || (frame.left - minFrameLeft).abs() < 0.1)
                ? separateCoverThickness
                : 0.0) -
            (hasSeparateCoverRight &&
                    (isOnlyFrame || (frame.right - maxFrameRight).abs() < 0.1)
                ? separateCoverThickness
                : 0.0);
        final frameHeight =
            (isOnlyFrame ? netHeight : frame.height) +
            weldAllowance -
            (hasSeparateCoverTop &&
                    (isOnlyFrame || (frame.top - minFrameTop).abs() < 0.1)
                ? separateCoverThickness
                : 0.0) -
            (hasSeparateCoverBottom &&
                    (isOnlyFrame || (frame.bottom - maxFrameBottom).abs() < 0.1)
                ? separateCoverThickness
                : 0.0);
        _paintProfileDimensionLabel(
          canvas,
          cutLabel(frameWidth, sideFrameCode('top')),
          Rect.fromLTWH(
            frame.left + 2,
            frame.top + 1,
            math.max(0.0, frame.width - 4),
            math.max(0.0, frameThickness - 2),
          ),
        );
        _paintProfileDimensionLabel(
          canvas,
          cutLabel(frameHeight, sideFrameCode('left')),
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

    // Custom standalone-cover segments have their own individual cutting
    // lengths in the cutting table, so no misleading full-side label is drawn.
    final showFullSeparateCover =
        hasSeparateCover && !model.useCustomSideCoverLayout;
    if (hasIntegratedCover || showFullSeparateCover) {
      final coverWidth = hasIntegratedCover
          ? integratedCoverWidth
          : separateCoverWidth;
      final coverCode = hasIntegratedCover ? frameCode : separateCoverCode;
      final coverWeldAllowance = hasSeparateCover && model.isFramePVC
          ? 5.0
          : 0.0;
      final coverCutWidth = hasIntegratedCover
          ? model.width + (2 * coverWidth) + weldAllowance
          : model.width + (2 * coverWidth) + coverWeldAllowance;
      final coverCutHeight = hasIntegratedCover
          ? model.height + (2 * coverWidth) + weldAllowance
          : model.height + (2 * coverWidth) + coverWeldAllowance;
      if (coverWidth > 0) {
        final isInternal = model.isInternalView;
        final hasLeft = hasIntegratedCover
            ? (isInternal
                  ? !model.removedShutterSides.contains('left')
                  : !model.removedShutterSides.contains('right'))
            : (isInternal ? hasSeparateCoverLeft : hasSeparateCoverRight);
        final hasTop = hasIntegratedCover
            ? !model.removedShutterSides.contains('top')
            : hasSeparateCoverTop;
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

  void _paintProfileDimensionLabel(
    Canvas canvas,
    String text,
    Rect bounds, {
    bool vertical = false,
    bool alignStart = false,
  }) {
    final crossAxis = vertical ? bounds.width : bounds.height;
    final mainAxis = vertical ? bounds.height : bounds.width;
    if (crossAxis < 12 || mainAxis < 35) return;

    double fontSize = math.min(34.0, math.max(15.0, crossAxis * 0.78));
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontSize: fontSize,
            fontWeight: FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width <= mainAxis - 8 || fontSize <= 10) break;
      fontSize -= 1.0;
    }
    if (painter.width > mainAxis - 4) return;

    canvas.save();
    if (vertical) {
      // Keep the full label above the middle hardware band.  This is
      // especially important for sliding leaves, which can have handles on
      // both outer stiles at the vertical midpoint.
      final halfLabelLength = painter.width / 2;
      final minimumY = bounds.top + halfLabelLength + 4;
      final maximumY = math.min(
        bounds.bottom - halfLabelLength - 4,
        bounds.top + (bounds.height * 0.44) - halfLabelLength,
      );
      if (minimumY > maximumY) {
        canvas.restore();
        return;
      }
      final preferredY = bounds.top + (bounds.height * 0.27);
      final labelY = preferredY.clamp(minimumY, maximumY).toDouble();
      final center = Offset(bounds.center.dx, labelY);
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

  /// Millimetres per screen pixel at the current zoom.
  double get _mmPerPx => 1 / math.max(1e-6, model.canvasScale * userScale);

  /// Outer dimensions are laid out in screen pixels (converted to mm) so
  /// they keep one readable size whatever the window size or zoom, never
  /// collide, and can be dragged away from the frame by the user.
  void _paintDimensions(Canvas canvas, WindowModel model, Offset pos) {
    double px(double value) => value * _mmPerPx;
    double dragged(String key) => model.dimensionOffsets[key] ?? 0.0;
    final double scW = model.sideCoverWidth;

    // Ends of slanted mullions on the outer sides, measured from the outer
    // frame edge like the reference workshop drawings (e.g. 437 | 1670).
    final topPts = <double>[];
    final bottomPts = <double>[];
    final leftPts = <double>[];
    final rightPts = <double>[];
    if (model.zones.isNotEmpty) {
      final minTop = model.zones.map((z) => z.boundary.top).reduce(math.min);
      final maxBottom = model.zones
          .map((z) => z.boundary.bottom)
          .reduce(math.max);
      final minLeft = model.zones.map((z) => z.boundary.left).reduce(math.min);
      final maxRight = model.zones
          .map((z) => z.boundary.right)
          .reduce(math.max);
      for (final zone in model.zones) {
        if (zone.slantedDividers.isEmpty) continue;
        final g = model.slantedGeometryFor(
          zone,
          dividers: model.slantedDividersShownFor(zone),
      );
        for (final d in g.dividers) {
          final (a, b) = g.centreLine(d);
          for (final (anchor, p) in [(d.start, a), (d.end, b)]) {
            switch (anchor.edge) {
              case ZoneEdge.top:
                if ((zone.boundary.top - minTop).abs() < 2) topPts.add(p.dx);
              case ZoneEdge.bottom:
                if ((zone.boundary.bottom - maxBottom).abs() < 2) {
                  bottomPts.add(p.dx);
                }
              case ZoneEdge.left:
                if ((zone.boundary.left - minLeft).abs() < 2) leftPts.add(p.dy);
              case ZoneEdge.right:
                if ((zone.boundary.right - maxRight).abs() < 2) {
                  rightPts.add(p.dy);
                }
            }
          }
        }
      }
    }

    void segmentRow(
      List<double> points, {
      required bool horizontal,
      required double at,
      required double start,
      required double end,
      required double edge,
    }) {
      if (points.isEmpty) return;
      final stops = <double>[start, ...points..sort(), end];
      for (var i = 0; i < stops.length - 1; i++) {
        final gap = stops[i + 1] - stops[i];
        if (gap < 1.0) continue;
        final text = '${(gap * 100).round() / 100}';
        _drawDimension(
          canvas,
          text,
          horizontal
              ? Offset(pos.dx + stops[i], at)
              : Offset(at, pos.dy + stops[i]),
          horizontal
              ? Offset(pos.dx + stops[i + 1], at)
              : Offset(at, pos.dy + stops[i + 1]),
          isVerticalLine: !horizontal,
          isSmall: true,
        );
      }
      for (final p in points) {
        _drawWitnessLine(
          canvas,
          horizontal ? Offset(pos.dx + p, edge) : Offset(edge, pos.dy + p),
          horizontal
              ? Offset(pos.dx + p, at + (at < edge ? -px(5) : px(5)))
              : Offset(at + (at < edge ? -px(5) : px(5)), pos.dy + p),
        );
      }
    }
    final physicalFrames = model.getPhysicalFrameInfos();
    final bool isMultiFrame = physicalFrames.length > 1;

    double offsetDistTop = px(isMultiFrame ? 92.0 : 44.0);
    // A row of slanted-mullion ends sits between the frame and the total.
    if (topPts.isNotEmpty) offsetDistTop += px(44.0);
    if (model.hasShutter) {
      offsetDistTop += px(16.0);
    }
    if (model.hasSideCovers && !model.removedShutterSides.contains('top')) {
      offsetDistTop += scW + 15.0;
    }
    double offsetDistLeft =
        px(leftPts.isEmpty ? 44.0 : 88.0) + dragged('left');
    if (model.hasSideCovers && !model.removedShutterSides.contains('left')) {
      offsetDistLeft += scW + 15.0;
    }
    double offsetDistRight =
        px(rightPts.isEmpty ? 44.0 : 88.0) + dragged('right');
    if (model.hasSideCovers && !model.removedShutterSides.contains('right')) {
      offsetDistRight += scW + 15.0;
    }
    if (model.shutterIsLongerThanWindow) {
      final shutterDimX = pos.dx + model.width + offsetDistRight + px(60.0);
      _drawDimension(
        canvas,
        'V ${model.shutterDrawingHeight.toInt()} mm',
        Offset(shutterDimX, pos.dy),
        Offset(shutterDimX, pos.dy + model.shutterDrawingHeight),
        isVerticalLine: true,
        isSmall: true,
      );
      _drawWitnessLine(
        canvas,
        Offset(pos.dx + model.width, pos.dy),
        Offset(shutterDimX + px(5.0), pos.dy),
      );
      _drawWitnessLine(
        canvas,
        Offset(pos.dx + model.width, pos.dy + model.shutterDrawingHeight),
        Offset(shutterDimX + px(5.0), pos.dy + model.shutterDrawingHeight),
      );
      offsetDistRight += px(56.0);
    }

    final bool isSlantedOrArched =
        model.archHeight > 0 ||
        model.topSlantLeftY != 0 ||
        model.topSlantRightY != 0 ||
        model.bottomSlantLeftY != 0 ||
        model.bottomSlantRightY != 0;

    double widthY;
    if (isSlantedOrArched) {
      double offsetDistBottom = px(bottomPts.isEmpty ? 44.0 : 88.0);
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
    // A shaped head moves the overall width below the frame.
    final double widthSide = isSlantedOrArched ? 1.0 : -1.0;
    widthY += widthSide * dragged('width');
    final double widthAnchorY = isSlantedOrArched
        ? pos.dy + model.height
        : pos.dy;

    // --- Width Dimensions ---
    final bool hasAngleJunction =
        model.usesProfileAngle && model.activeProfileAngleJunctions.isNotEmpty;

    // Outer/total width is always shown on the top dimension layer, including
    // when the opening is composed of multiple frames joined by an angle.
    _drawDimension(
      canvas,
      '${model.width.toInt()} mm',
      Offset(pos.dx, widthY),
      Offset(pos.dx + model.width, widthY),
      isVerticalLine: false,
      tapKey: 'width',
      dragKey: 'width',
      normal: Offset(0, widthSide),
    );
    // Witness lines for total width, from the frame edge they measure.
    _drawWitnessLine(
      canvas,
      Offset(pos.dx, widthAnchorY),
      Offset(pos.dx, widthY + widthSide * px(6.0)),
    );
    _drawWitnessLine(
      canvas,
      Offset(pos.dx + model.width, widthAnchorY),
      Offset(pos.dx + model.width, widthY + widthSide * px(6.0)),
    );

    final double coverTop =
        model.hasSideCovers && !model.removedShutterSides.contains('top')
        ? scW + 15.0
        : 0.0;
    final double coverBottom =
        model.hasSideCovers && !model.removedShutterSides.contains('bottom')
        ? scW + 15.0
        : 0.0;
    final double coverLeft =
        model.hasSideCovers && !model.removedShutterSides.contains('left')
        ? scW + 15.0
        : 0.0;
    final double coverRight =
        model.hasSideCovers && !model.removedShutterSides.contains('right')
        ? scW + 15.0
        : 0.0;
    segmentRow(
      topPts,
      horizontal: true,
      at: pos.dy - coverTop - px(44.0),
      start: 0,
      end: model.width,
      edge: pos.dy,
    );
    segmentRow(
      bottomPts,
      horizontal: true,
      // Coupled frames keep their own width chain right under the frame.
      at: pos.dy + model.height + coverBottom + px(isMultiFrame ? 88.0 : 44.0),
      start: 0,
      end: model.width,
      edge: pos.dy + model.height,
    );
    segmentRow(
      leftPts,
      horizontal: false,
      at: pos.dx - coverLeft - px(44.0),
      start: 0,
      end: model.height,
      edge: pos.dx,
    );
    segmentRow(
      rightPts,
      horizontal: false,
      at: pos.dx + model.width + coverRight + px(44.0),
      start: 0,
      end: model.height,
      edge: pos.dx + model.width,
    );

    // Coupled frames: every frame gets its own dimension, in chains along
    // the outline (see WindowModel.frameDimensionChains); each number opens
    // that frame's own resize dialog.
    final chains = model.frameDimensionChains();
    if (isMultiFrame && !isSlantedOrArched) {
      double bottomY = pos.dy + model.height + px(44.0) + dragged('bottom');
      if (model.hasSideCovers &&
          model.hasBottomFrame &&
          !model.removedShutterSides.contains('bottom')) {
        bottomY += scW + 15.0;
      }
      for (final f in chains.bottom) {
        final double x0 = pos.dx + f.rect.left;
        final double x1 = pos.dx + f.rect.right;
        _drawDimension(
          canvas,
          '${f.rect.width.round()} mm',
          Offset(x0, bottomY),
          Offset(x1, bottomY),
          isSmall: true,
          tapKey: 'frameW:${f.primaryZoneId}',
        );
        _drawWitnessLine(
          canvas,
          Offset(x0, pos.dy + f.rect.bottom),
          Offset(x0, bottomY + px(5.0)),
        );
        _drawWitnessLine(
          canvas,
          Offset(x1, pos.dy + f.rect.bottom),
          Offset(x1, bottomY + px(5.0)),
        );
      }
      for (final f in chains.innerWidths) {
        // A middle row: its width inside the frame, under its head.
        final y =
            pos.dy + f.rect.top + math.min(f.rect.height * 0.28, px(40.0));
        _drawDimension(
          canvas,
          '${f.rect.width.round()} mm',
          Offset(pos.dx + f.rect.left, y),
          Offset(pos.dx + f.rect.right, y),
          isSmall: true,
          tapKey: 'frameW:${f.primaryZoneId}',
        );
      }
    }
    if (isMultiFrame && chains.top.isNotEmpty) {
      // Keep individual frame dimensions close to the drawing, directly
      // below the overall width dimension.
      double layer1Y = widthY + px(40.0);
      final topChain = chains.top;
      for (int fi = 0; fi < topChain.length; fi++) {
        final f = topChain[fi];
        final double x0 = pos.dx + f.rect.left;
        final double x1 = pos.dx + f.rect.right;
        _drawDimension(
          canvas,
          '${f.rect.width.round()} mm',
          Offset(x0, layer1Y),
          Offset(x1, layer1Y),
          isVerticalLine: false,
          isSmall: true,
          tapKey: 'frameW:${f.primaryZoneId}',
        );
        // Vertical witness ticks connecting to frame
        _drawWitnessLine(
          canvas,
          Offset(x0, pos.dy + f.rect.top),
          Offset(x0, layer1Y - px(5.0)),
        );
        _drawWitnessLine(
          canvas,
          Offset(x1, pos.dy + f.rect.top),
          Offset(x1, layer1Y - px(5.0)),
        );

        if (hasAngleJunction && fi < topChain.length - 1) {
          // Draw 90° angle symbol at the junction point
          final jX = x1;
          final angleTextPainter = TextPainter(
            text: TextSpan(
              text: '∟ 90°',
              style: TextStyle(
                color: const Color(0xFF1E88E5),
                fontSize: px(12.0),
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          angleTextPainter.paint(
            canvas,
            Offset(jX - angleTextPainter.width / 2, layer1Y - px(20.0)),
          );
        }
      }
    }

    // --- Height Dimensions ---
    if (isMultiFrame) {
      if (model.hasShutter) {
        double boxSize = model.shutterBoxHeight;
        _drawDimension(
          canvas,
          '${boxSize.toInt()} mm',
          Offset(pos.dx - offsetDistLeft, pos.dy),
          Offset(pos.dx - offsetDistLeft, pos.dy + boxSize),
          isVerticalLine: true,
          isSmall: true,
          labelOffset: Offset(-px(18.0), 0),
        );
      }

      void frameHeightChain(
        List<PhysicalFrameInfo> chain,
        double dimX,
        double side,
      ) {
        for (final f in chain) {
          final double startY = pos.dy + f.rect.top;
          final double endY = pos.dy + f.rect.bottom;
          final double edgeX = pos.dx + (side < 0 ? f.rect.left : f.rect.right);
      _drawDimension(
        canvas,
            '${f.rect.height.round()} mm',
            Offset(dimX, startY),
            Offset(dimX, endY),
        isVerticalLine: true,
            isSmall: true,
            tapKey: 'frameH:${f.primaryZoneId}',
      );
      _drawWitnessLine(
        canvas,
            Offset(edgeX, startY),
            Offset(dimX + side * px(8.0), startY),
      );
      _drawWitnessLine(
        canvas,
            Offset(edgeX, endY),
            Offset(dimX + side * px(8.0), endY),
      );
        }
      }

      // Frames along the left outline, then the overall height outside them.
      final double leftDimX = pos.dx - offsetDistLeft;
      frameHeightChain(chains.left, leftDimX, -1.0);
      final double totalDimX = chains.left.isEmpty
          ? leftDimX
          : leftDimX - px(44.0);
        _drawDimension(
          canvas,
        '${model.height.round()} mm',
          Offset(totalDimX, pos.dy),
          Offset(totalDimX, pos.dy + model.height),
          isVerticalLine: true,
        tapKey: 'height',
        dragKey: 'left',
        normal: const Offset(-1, 0),
        );
        _drawWitnessLine(
          canvas,
          Offset(pos.dx, pos.dy),
        Offset(totalDimX - px(8.0), pos.dy),
        );
        _drawWitnessLine(
          canvas,
          Offset(pos.dx, pos.dy + model.height),
        Offset(totalDimX - px(8.0), pos.dy + model.height),
        );

      // Frames along the right outline (when not already measured left).
      frameHeightChain(
        chains.right,
        pos.dx + model.width + offsetDistRight,
        1.0,
      );

      // A middle column: its height inside the frame, off-centre.
      for (final f in chains.innerHeights) {
          final double dimX =
            pos.dx + f.rect.left + math.min(f.rect.width * 0.28, 65.0);
          _drawDimension(
            canvas,
          '${f.rect.height.round()} mm',
          Offset(dimX, pos.dy + f.rect.top),
          Offset(dimX, pos.dy + f.rect.bottom),
            isVerticalLine: true,
            isSmall: true,
          tapKey: 'frameH:${f.primaryZoneId}',
          );
        }
    } else {
      // --- Single Frame Height (Existing behavior) ---
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
            labelOffset: Offset(-px(18.0), 0),
          );

          double windowHeight = model.height;
          _drawDimension(
            canvas,
            '${windowHeight.toInt()} mm',
            Offset(pos.dx - offsetDistLeft, pos.dy),
            Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
            isVerticalLine: true,
            tapKey: 'height',
            dragKey: 'left',
            normal: const Offset(-1, 0),
          );
        } else {
          _drawDimension(
            canvas,
            '${boxSize.toInt()} mm',
            Offset(pos.dx - offsetDistLeft, pos.dy),
            Offset(pos.dx - offsetDistLeft, pos.dy + boxSize),
            isVerticalLine: true,
            isSmall: true,
            labelOffset: Offset(-px(18.0), 0),
          );

          double windowHeight = model.height - boxSize;
          _drawDimension(
            canvas,
            '${windowHeight.toInt()} mm',
            Offset(pos.dx - offsetDistLeft, pos.dy + boxSize),
            Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
            isVerticalLine: true,
            tapKey: 'height',
            dragKey: 'left',
            normal: const Offset(-1, 0),
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

        // Left jamb (the whole height on a plain frame).
        final double leftDimX = pos.dx - offsetDistLeft;
        final double startY = pos.dy + model.topSlantLeftY;
        final double endY = pos.dy + model.height - model.bottomSlantLeftY;
        _drawDimension(
          canvas,
          '${leftH.round()} mm',
          Offset(leftDimX, startY),
          Offset(leftDimX, endY),
          isVerticalLine: true,
          tapKey: isSlantedOrArched ? 'leftJamb' : 'height',
          dragKey: 'left',
          normal: const Offset(-1, 0),
        );
        if (isSlantedOrArched) {
          _drawWitnessLine(
            canvas,
            Offset(pos.dx, startY),
            Offset(leftDimX - px(6.0), startY),
          );
          _drawWitnessLine(
            canvas,
            Offset(pos.dx, endY),
            Offset(leftDimX - px(6.0), endY),
        );
        }

        // Right jamb whenever it differs from the left one.
        if (isSlanted) {
          final double rightDimX = pos.dx + model.width + offsetDistRight;
          final double startYRight = pos.dy + model.topSlantRightY;
          final double endYRight =
              pos.dy + model.height - model.bottomSlantRightY;
          _drawDimension(
            canvas,
            '${rightH.round()} mm',
            Offset(rightDimX, startYRight),
            Offset(rightDimX, endYRight),
            isVerticalLine: true,
            tapKey: 'rightJamb',
            dragKey: 'right',
            normal: const Offset(1, 0),
          );
          _drawWitnessLine(
            canvas,
            Offset(pos.dx + model.width, startYRight),
            Offset(rightDimX + px(6.0), startYRight),
          );
          _drawWitnessLine(
            canvas,
            Offset(pos.dx + model.width, endYRight),
            Offset(rightDimX + px(6.0), endYRight),
          );
          }

        final arc = model.headArc(topOffset: pos.dy);
        final chordStart = Offset(pos.dx, pos.dy + model.topSlantLeftY);
        final chordEnd = Offset(
          pos.dx + model.width,
          pos.dy + model.topSlantRightY,
        );
        final chord = chordEnd - chordStart;
        if (arc != null) {
          // Arch rise, measured from the springing line up to the apex. It
          // stacks on the left jamb when the springing line is level.
          if ((model.topSlantLeftY - model.topSlantRightY).abs() < 1.0) {
            final apexY = arc.apex.dy;
          _drawDimension(
            canvas,
              '${model.archHeight.round()} mm',
              Offset(leftDimX, apexY),
              Offset(leftDimX, startY),
            isVerticalLine: true,
              tapKey: 'archRise',
              dragKey: 'left',
              normal: const Offset(-1, 0),
            );
            _drawWitnessLine(
              canvas,
              arc.apex,
              Offset(leftDimX - px(6.0), apexY),
          );
          } else {
            _drawAlignedDimension(
              canvas,
              '${model.archHeight.round()} mm',
              (chordStart + chordEnd) / 2,
              arc.apex,
              tapKey: 'archRise',
              dragKey: 'archRise',
              normal: Offset.zero,
            );
          }

          // Total height of the arched frame, from its bottom up to the
          // apex, beside the right jamb.
          final apexTop = arc.apex.dy;
          final frameBottom =
              pos.dy +
              model.height -
              math.min(model.bottomSlantLeftY, model.bottomSlantRightY);
          final totalX =
              pos.dx +
              model.width +
              offsetDistRight +
              (isSlanted ? px(70.0) : 0.0) +
              dragged('archTotal');
          _drawDimension(
            canvas,
            '${(frameBottom - apexTop).round()} mm',
            Offset(totalX, apexTop),
            Offset(totalX, frameBottom),
            isVerticalLine: true,
            dragKey: 'archTotal',
            normal: const Offset(1, 0),
          );
          _drawWitnessLine(
            canvas,
            arc.apex,
            Offset(totalX + px(6.0), apexTop),
          );
          _drawWitnessLine(
            canvas,
            Offset(pos.dx + model.width, frameBottom),
            Offset(totalX + px(6.0), frameBottom),
          );

          // Chord of the arch, corner to corner: parallel to it, beyond the
          // arch, with a witness line from each corner (as for a slanted
          // head).
          if (chord.distance > 0) {
            final d = chord / chord.distance;
            final outward = Offset(d.dy, -d.dx);
            final rise = (arc.apex - (chordStart + chordEnd) / 2).distance;
            double dist = rise + px(44.0) + dragged('archChord');
            if (model.hasSideCovers &&
                !model.removedShutterSides.contains('top')) {
              dist += scW + 15.0;
            }
            final q1 = chordStart + outward * dist;
            final q2 = chordEnd + outward * dist;
            _drawAlignedDimension(
              canvas,
              '${chord.distance.round()} mm',
              q1,
              q2,
              dragKey: 'archChord',
              normal: outward,
            );
            _drawWitnessLine(canvas, chordStart, q1 + outward * px(6.0));
            _drawWitnessLine(canvas, chordEnd, q2 + outward * px(6.0));
          }
        } else if (chord.distance > 0 &&
            (model.topSlantLeftY - model.topSlantRightY).abs() >= 1.0) {
          // Slanted head: its true length, parallel to it and outside it.
          final d = chord / chord.distance;
          final outward = Offset(d.dy, -d.dx);
          double dist = px(44.0) + dragged('slant');
          if (model.hasSideCovers &&
              !model.removedShutterSides.contains('top')) {
            dist += scW + 15.0;
          }
          final q1 = chordStart + outward * dist;
          final q2 = chordEnd + outward * dist;
          _drawAlignedDimension(
            canvas,
            '${chord.distance.round()} mm',
            q1,
            q2,
            tapKey: 'slant',
            dragKey: 'slant',
            normal: outward,
          );
          _drawWitnessLine(canvas, chordStart, q1 + outward * px(6.0));
          _drawWitnessLine(canvas, chordEnd, q2 + outward * px(6.0));
        }
      }
    }
  }

  void _drawWitnessLine(Canvas canvas, Offset p1, Offset p2) {
    final p = Paint()
      ..color = _dimensionWitnessColor
      ..strokeWidth = 0.9 * _mmPerPx;
    canvas.drawLine(p1, p2, p);
  }

  /// Records a painted label so taps (edit) and drags (move) hit it.
  void _recordDimensionHit(
    String? tapKey,
    String? dragKey,
    Offset center,
    Size textSize,
    double angle,
    Offset normal,
  ) {
    if (tapKey == null && dragKey == null) return;
    final c = math.cos(angle).abs();
    final s = math.sin(angle).abs();
    final w = textSize.width * c + textSize.height * s;
    final h = textSize.width * s + textSize.height * c;
    model.dimensionLabelHits.add(
      DimensionLabelHit(
        tapKey ?? '',
        dragKey ?? '',
        Rect.fromCenter(center: center, width: w, height: h)
            .inflate(10.0 * _mmPerPx),
        normal,
      ),
    );
  }

  void _drawDimension(
    Canvas canvas,
    String text,
    Offset p1,
    Offset p2, {
    bool isVerticalLine = false,
    bool isSmall = false,
    String? tapKey,
    String? dragKey,
    Offset normal = Offset.zero,
    Offset labelOffset = Offset.zero,
  }) {
    final double midX = (p1.dx + p2.dx) / 2;
    final double midY = (p1.dy + p2.dy) / 2;
    final Offset lineCenter = Offset(midX, midY);
    final Offset labelCenter = lineCenter + labelOffset;

    final Size textSize = _drawText(
      canvas,
      text,
      labelCenter,
      isVertical: isVerticalLine,
      isSmall: isSmall,
    );
    _recordDimensionHit(
      tapKey,
      dragKey,
      labelCenter,
      textSize,
      isVerticalLine ? -math.pi / 2 : 0.0,
      normal,
    );

    _drawArrow(
      canvas,
      p1,
      p2,
      isVerticalLine: isVerticalLine,
      textGap: labelOffset == Offset.zero
          ? textSize.width + 16.0 * _mmPerPx
          : 0.0,
    );
  }

  /// Dimension along any direction (slanted head, arch rise): line with
  /// perpendicular ticks and arrowheads, text kept upright along the line.
  void _drawAlignedDimension(
    Canvas canvas,
    String text,
    Offset p1,
    Offset p2, {
    String? tapKey,
    String? dragKey,
    Offset normal = Offset.zero,
  }) {
    final delta = p2 - p1;
    final length = delta.distance;
    if (length <= 0) return;
    final d = delta / length;
    var angle = math.atan2(d.dy, d.dx);
    if (angle > math.pi / 2) angle -= math.pi;
    if (angle < -math.pi / 2) angle += math.pi;
    final center = (p1 + p2) / 2;

    final tp = _dimensionTextPainter(text, isSmall: false);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    _recordDimensionHit(tapKey, dragKey, center, tp.size, angle, normal);

    final paint = Paint()
      ..color = _dimensionLineColor
      ..strokeWidth = 1.2 * _mmPerPx;
    final halfGap = math.min(length / 2, (tp.width + 16.0 * _mmPerPx) / 2);
    canvas.drawLine(p1, center - d * halfGap, paint);
    canvas.drawLine(center + d * halfGap, p2, paint);
    final n = Offset(-d.dy, d.dx);
    final tick = 7.0 * _mmPerPx;
    canvas.drawLine(p1 - n * tick, p1 + n * tick, paint);
    canvas.drawLine(p2 - n * tick, p2 + n * tick, paint);
    final arrowLen = 9.0 * _mmPerPx;
    final arrowW = 3.5 * _mmPerPx;
    final fill = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(
          (p1 + d * arrowLen + n * arrowW).dx,
          (p1 + d * arrowLen + n * arrowW).dy,
        )
        ..lineTo(
          (p1 + d * arrowLen - n * arrowW).dx,
          (p1 + d * arrowLen - n * arrowW).dy,
        )
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p2.dx, p2.dy)
        ..lineTo(
          (p2 - d * arrowLen + n * arrowW).dx,
          (p2 - d * arrowLen + n * arrowW).dy,
        )
        ..lineTo(
          (p2 - d * arrowLen - n * arrowW).dx,
          (p2 - d * arrowLen - n * arrowW).dy,
        )
        ..close(),
      fill,
    );
  }

  /// Plain, large, constant-size digits (no heavy weight or shadow).
  TextPainter _dimensionTextPainter(String text, {required bool isSmall}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _dimensionTextColor,
          fontWeight: isDarkMode ? FontWeight.w600 : FontWeight.w500,
          fontSize: (isSmall ? 16.0 : 21.0) * _mmPerPx,
          shadows: isDarkMode
              ? const [
            Shadow(
                    color: Color(0x99000000),
                    blurRadius: 2.0,
                    offset: Offset(0, 0.8),
            ),
                ]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  Size _drawText(
    Canvas canvas,
    String text,
    Offset center, {
    bool isVertical = false,
    bool isSmall = false,
  }) {
    final tp = _dimensionTextPainter(text, isSmall: isSmall);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (isVertical) canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    return tp.size;
  }

  void _drawArrow(
    Canvas canvas,
    Offset p1,
    Offset p2, {
    bool isVerticalLine = false,
    double textGap = 100.0,
  }) {
    final p = Paint()
      ..color = _dimensionLineColor
      ..strokeWidth = 1.2 * _mmPerPx;

    double tickSize = 7.0 * _mmPerPx;

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

      // Arrowheads pointing to ends
      final double arrowLen = 9.0 * _mmPerPx;
      final double arrowW = 3.5 * _mmPerPx;
      final arrowPaint = Paint()
        ..color = p.color
        ..style = PaintingStyle.fill;
      final topArrow = Path()
        ..moveTo(p1.dx, minY)
        ..lineTo(p1.dx - arrowW, minY + arrowLen)
        ..lineTo(p1.dx + arrowW, minY + arrowLen)
        ..close();
      canvas.drawPath(topArrow, arrowPaint);
      final bottomArrow = Path()
        ..moveTo(p2.dx, maxY)
        ..lineTo(p2.dx - arrowW, maxY - arrowLen)
        ..lineTo(p2.dx + arrowW, maxY - arrowLen)
        ..close();
      canvas.drawPath(bottomArrow, arrowPaint);
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

      // Arrowheads pointing to ends
      final double arrowLen = 9.0 * _mmPerPx;
      final double arrowW = 3.5 * _mmPerPx;
      final arrowPaint = Paint()
        ..color = p.color
        ..style = PaintingStyle.fill;
      final leftArrow = Path()
        ..moveTo(minX, p1.dy)
        ..lineTo(minX + arrowLen, p1.dy - arrowW)
        ..lineTo(minX + arrowLen, p1.dy + arrowW)
        ..close();
      canvas.drawPath(leftArrow, arrowPaint);
      final rightArrow = Path()
        ..moveTo(maxX, p2.dy)
        ..lineTo(maxX - arrowLen, p2.dy - arrowW)
        ..lineTo(maxX - arrowLen, p2.dy + arrowW)
        ..close();
      canvas.drawPath(rightArrow, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AppWorkspacePainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.userScale != userScale ||
        oldDelegate.userPan != userPan ||
        oldDelegate.isDarkMode != isDarkMode;
  }
}

/// Marks an option that must stay in a specific visual row of the compact
/// two-row toolbar. This is used by mixed systems so opening-frame profiles
/// never get interleaved with sliding-frame profiles.
class _Tier2RowItem extends StatelessWidget {
  final int rowIndex;
  final Widget child;

  const _Tier2RowItem({required this.rowIndex, required this.child});

  @override
  Widget build(BuildContext context) => child;
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
        name: label,
        imagePath: imagePath,
        size: 24.0,
        fallbackIcon: Icons.image_not_supported_rounded,
        fallbackColor: selected ? Colors.blue.shade600 : Colors.grey.shade400,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
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

// Helper validation functions for glass/gasket thickness constraints (Ouvrant & Coulissant)
bool isGlassThicknessValid(
  double thickVal,
  GlassSpecification spec,
  WindowModel model,
  String systemMode,
) {
  final isSliding =
      systemMode == 'sliding' ||
      model.systemMode == 'sliding' ||
      model.zones.any((zone) => zone.content == ZoneContent.slidingSash);
  final double jointAllowance;
  if (isSliding) {
    final double j = model.selectedVitrageJointThickness(fallback: 2.0);
    jointAllowance = spec.jointTwoSides ? (j * 2) : j;
  } else {
    jointAllowance =
        model.selectedVitrageJointThickness(fallback: 2.0) +
        (spec.structure == GlassStructure.double
            ? model.selectedBourrageJointThickness(
                doubleGlass: true,
                fallback: 2.0,
              )
            : 0.0);
  }
  final maxCapacity = model.glazingCapacityForStructure(
    spec.structure,
    sliding: isSliding,
  );
  if (maxCapacity != null && (thickVal + jointAllowance) > maxCapacity) {
    return false;
  }
  return true;
}

bool isDoubleGlassValid(
  double thickOuter,
  int intercall,
  double thickInner,
  bool jointTwoSides,
  WindowModel model,
  String systemMode,
) {
  final isSliding =
      systemMode == 'sliding' ||
      model.systemMode == 'sliding' ||
      model.zones.any((zone) => zone.content == ZoneContent.slidingSash);
  final double jointAllowance;
  if (isSliding) {
    final double j = model.selectedVitrageJointThickness(fallback: 2.0);
    jointAllowance = jointTwoSides ? (j * 2) : j;
  } else {
    jointAllowance =
        model.selectedVitrageJointThickness(fallback: 2.0) +
        model.selectedBourrageJointThickness(doubleGlass: true, fallback: 2.0);
  }
  final maxCapacity = model.glazingCapacityForStructure(
    GlassStructure.double,
    sliding: isSliding,
  );
  if (maxCapacity != null &&
      (thickOuter + intercall + thickInner + jointAllowance) > maxCapacity) {
    return false;
  }
  return true;
}

class _PresetThumbnailWidget extends StatelessWidget {
  final WindowPresetType preset;
  final double width;
  final double height;
  final bool isDark;
  final Color? accentColor;

  const _PresetThumbnailWidget({
    required this.preset,
    this.width = 64,
    this.height = 64,
    required this.isDark,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161622) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (accentColor ?? Colors.blue).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(width, height),
          painter: _PresetThumbnailPainter(
            preset: preset,
            isDark: isDark,
            accentColor: accentColor ?? Colors.blue,
          ),
        ),
      ),
    );
  }
}

class _PresetThumbnailPainter extends CustomPainter {
  final WindowPresetType preset;
  final bool isDark;
  final Color accentColor;

  _PresetThumbnailPainter({
    required this.preset,
    required this.isDark,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final frameBorderColor = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF334155);
    final frameFillColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final glassFillColor = isDark
        ? const Color(0xFF0F2B48)
        : const Color(0xFFE0F2FE);
    final glassSheenColor = Colors.white.withValues(
      alpha: isDark ? 0.15 : 0.45,
    );
    final sashBorderColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569);
    final sashFillColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF8FAFC);
    final openLineColor = accentColor.withValues(alpha: 0.85);
    final shutterBoxColor = isDark
        ? const Color(0xFF475569)
        : const Color(0xFFCBD5E1);
    final shutterBladeColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final handleColor = isDark
        ? Colors.amber.shade300
        : const Color(0xFFD97706);

    final framePaint = Paint()
      ..color = frameFillColor
      ..style = PaintingStyle.fill;

    final frameBorderPaint = Paint()
      ..color = frameBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final sashBorderPaint = Paint()
      ..color = sashBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final sashFillPaint = Paint()
      ..color = sashFillColor
      ..style = PaintingStyle.fill;

    final glassPaint = Paint()
      ..color = glassFillColor
      ..style = PaintingStyle.fill;

    final openLinePaint = Paint()
      ..color = openLineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    void drawGlass(Rect glassRect) {
      canvas.drawRect(glassRect, glassPaint);
      final sheenPaint = Paint()
        ..color = glassSheenColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      final p1 = Offset(
        glassRect.left + glassRect.width * 0.15,
        glassRect.bottom - glassRect.height * 0.15,
      );
      final p2 = Offset(
        glassRect.left + glassRect.width * 0.45,
        glassRect.top + glassRect.height * 0.15,
      );
      canvas.drawLine(p1, p2, sheenPaint);
      final p3 = Offset(
        glassRect.left + glassRect.width * 0.5,
        glassRect.bottom - glassRect.height * 0.15,
      );
      final p4 = Offset(
        glassRect.left + glassRect.width * 0.8,
        glassRect.top + glassRect.height * 0.15,
      );
      canvas.drawLine(p3, p4, sheenPaint);
    }

    void drawOpenTriangles(Rect sashRect, {required bool hingesLeft}) {
      final path = Path();
      if (hingesLeft) {
        path.moveTo(sashRect.left, sashRect.top);
        path.lineTo(sashRect.right, sashRect.center.dy);
        path.lineTo(sashRect.left, sashRect.bottom);
      } else {
        path.moveTo(sashRect.right, sashRect.top);
        path.lineTo(sashRect.left, sashRect.center.dy);
        path.lineTo(sashRect.right, sashRect.bottom);
      }
      canvas.drawPath(path, openLinePaint);
    }

    void drawTopOpenTriangle(Rect sashRect) {
      final path = Path()
        ..moveTo(sashRect.left, sashRect.bottom)
        ..lineTo(sashRect.center.dx, sashRect.top)
        ..lineTo(sashRect.right, sashRect.bottom);
      canvas.drawPath(path, openLinePaint);
    }

    void drawSlidingArrows(Rect rect, {required bool isLeftSash}) {
      final arrowPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      final cy = rect.center.dy;
      final arrowW = rect.width * 0.42;
      if (isLeftSash) {
        final startX = rect.center.dx - arrowW / 2;
        final endX = rect.center.dx + arrowW / 2;
        canvas.drawLine(Offset(startX, cy), Offset(endX, cy), arrowPaint);
        canvas.drawLine(
          Offset(endX - 2.5, cy - 2.5),
          Offset(endX, cy),
          arrowPaint,
        );
        canvas.drawLine(
          Offset(endX - 2.5, cy + 2.5),
          Offset(endX, cy),
          arrowPaint,
        );
      } else {
        final startX = rect.center.dx + arrowW / 2;
        final endX = rect.center.dx - arrowW / 2;
        canvas.drawLine(Offset(startX, cy), Offset(endX, cy), arrowPaint);
        canvas.drawLine(
          Offset(endX + 2.5, cy - 2.5),
          Offset(endX, cy),
          arrowPaint,
        );
        canvas.drawLine(
          Offset(endX + 2.5, cy + 2.5),
          Offset(endX, cy),
          arrowPaint,
        );
      }
    }

    void drawShutterBox(Rect boxRect) {
      final boxPaint = Paint()
        ..color = shutterBoxColor
        ..style = PaintingStyle.fill;
      final boxBorder = Paint()
        ..color = frameBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(2)),
        boxPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(2)),
        boxBorder,
      );

      final bladePaint = Paint()
        ..color = shutterBladeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      const count = 3;
      final step = boxRect.height / (count + 1);
      for (var i = 1; i <= count; i++) {
        final y = boxRect.top + i * step;
        canvas.drawLine(
          Offset(boxRect.left + 2, y),
          Offset(boxRect.right - 2, y),
          bladePaint,
        );
      }
    }

    switch (preset) {
      case WindowPresetType.shutterOnly:
        final boxH = size.height * 0.28;
        final boxRect = Rect.fromLTWH(2, 2, size.width - 4, boxH);
        drawShutterBox(boxRect);
        final railW = 4.0;
        final railY = boxRect.bottom;
        final railH = size.height - railY - 2;
        final leftRail = Rect.fromLTWH(2, railY, railW, railH);
        final rightRail = Rect.fromLTWH(
          size.width - 2 - railW,
          railY,
          railW,
          railH,
        );
        canvas.drawRect(leftRail, framePaint);
        canvas.drawRect(leftRail, frameBorderPaint);
        canvas.drawRect(rightRail, framePaint);
        canvas.drawRect(rightRail, frameBorderPaint);
        final innerW = size.width - 4 - 2 * railW;
        const bladeCount = 7;
        final bladeStep = railH / (bladeCount + 1);
        final bladePaint = Paint()
          ..color = shutterBladeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9;
        for (var i = 1; i <= bladeCount; i++) {
          final y = railY + i * bladeStep;
          canvas.drawLine(
            Offset(2 + railW, y),
            Offset(size.width - 2 - railW, y),
            bladePaint,
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(2 + railW, railY + railH - 3.5, innerW, 3.5),
          Paint()
            ..color = frameBorderColor
            ..style = PaintingStyle.fill,
        );
        break;

      case WindowPresetType.singleDoor:
        final doorW = size.width * 0.65;
        final doorX = (size.width - doorW) / 2;
        final doorRect = Rect.fromLTWH(doorX, 2, doorW, size.height - 4);
        canvas.drawRect(doorRect, framePaint);
        canvas.drawRect(doorRect, frameBorderPaint);
        canvas.drawLine(
          Offset(doorX - 2, doorRect.bottom),
          Offset(doorX + doorW + 2, doorRect.bottom),
          Paint()
            ..color = frameBorderColor
            ..strokeWidth = 2.0,
        );
        const sashPad = 3.2;
        final sashRect = Rect.fromLTRB(
          doorRect.left + sashPad,
          doorRect.top + sashPad,
          doorRect.right - sashPad,
          doorRect.bottom - 1.5,
        );
        canvas.drawRect(sashRect, sashFillPaint);
        canvas.drawRect(sashRect, sashBorderPaint);
        final glassRect = Rect.fromLTRB(
          sashRect.left + 3.0,
          sashRect.top + 3.0,
          sashRect.right - 3.0,
          sashRect.top + sashRect.height * 0.62,
        );
        drawGlass(glassRect);
        canvas.drawRect(glassRect, sashBorderPaint);
        final panelRect = Rect.fromLTRB(
          sashRect.left + 3.0,
          glassRect.bottom + 2.5,
          sashRect.right - 3.0,
          sashRect.bottom - 3.5,
        );
        canvas.drawRect(panelRect, framePaint);
        canvas.drawRect(panelRect, sashBorderPaint);
        final handleX = sashRect.right - 4.5;
        final handleY = sashRect.top + sashRect.height * 0.52;
        canvas.drawCircle(
          Offset(handleX, handleY),
          1.8,
          Paint()..color = handleColor,
        );
        canvas.drawLine(
          Offset(handleX, handleY),
          Offset(handleX - 4, handleY),
          Paint()
            ..color = handleColor
            ..strokeWidth = 1.3,
        );
        canvas.drawCircle(
          Offset(handleX, handleY + 3.5),
          0.9,
          Paint()..color = handleColor,
        );
        drawOpenTriangles(sashRect, hingesLeft: true);
        break;

      case WindowPresetType.doubleDoor:
        final doorW = size.width * 0.88;
        final doorX = (size.width - doorW) / 2;
        final doorRect = Rect.fromLTWH(doorX, 2, doorW, size.height - 4);
        canvas.drawRect(doorRect, framePaint);
        canvas.drawRect(doorRect, frameBorderPaint);
        canvas.drawLine(
          Offset(doorX - 2, doorRect.bottom),
          Offset(doorX + doorW + 2, doorRect.bottom),
          Paint()
            ..color = frameBorderColor
            ..strokeWidth = 2.0,
        );
        const sashPad = 3.0;
        final innerW = doorRect.width - 2 * sashPad;
        final leafW = innerW / 2;
        final leftSash = Rect.fromLTWH(
          doorRect.left + sashPad,
          doorRect.top + sashPad,
          leafW - 0.5,
          doorRect.height - sashPad - 1.5,
        );
        canvas.drawRect(leftSash, sashFillPaint);
        canvas.drawRect(leftSash, sashBorderPaint);
        final leftGlass = Rect.fromLTRB(
          leftSash.left + 2.5,
          leftSash.top + 2.5,
          leftSash.right - 2.5,
          leftSash.top + leftSash.height * 0.62,
        );
        drawGlass(leftGlass);
        canvas.drawRect(leftGlass, sashBorderPaint);
        final leftPanel = Rect.fromLTRB(
          leftSash.left + 2.5,
          leftGlass.bottom + 2.0,
          leftSash.right - 2.5,
          leftSash.bottom - 3.5,
        );
        canvas.drawRect(leftPanel, framePaint);
        canvas.drawRect(leftPanel, sashBorderPaint);
        drawOpenTriangles(leftSash, hingesLeft: true);
        final rightSash = Rect.fromLTWH(
          doorRect.left + sashPad + leafW + 0.5,
          doorRect.top + sashPad,
          leafW - 0.5,
          doorRect.height - sashPad - 1.5,
        );
        canvas.drawRect(rightSash, sashFillPaint);
        canvas.drawRect(rightSash, sashBorderPaint);
        final rightGlass = Rect.fromLTRB(
          rightSash.left + 2.5,
          rightSash.top + 2.5,
          rightSash.right - 2.5,
          rightSash.top + rightSash.height * 0.62,
        );
        drawGlass(rightGlass);
        canvas.drawRect(rightGlass, sashBorderPaint);
        final rightPanel = Rect.fromLTRB(
          rightSash.left + 2.5,
          rightGlass.bottom + 2.0,
          rightSash.right - 2.5,
          rightSash.bottom - 3.5,
        );
        canvas.drawRect(rightPanel, framePaint);
        canvas.drawRect(rightPanel, sashBorderPaint);
        drawOpenTriangles(rightSash, hingesLeft: false);
        final midY = leftSash.top + leftSash.height * 0.52;
        canvas.drawCircle(
          Offset(leftSash.right - 2.0, midY),
          1.5,
          Paint()..color = handleColor,
        );
        canvas.drawCircle(
          Offset(rightSash.left + 2.0, midY),
          1.5,
          Paint()..color = handleColor,
        );
        break;

      case WindowPresetType.topOpeningSmallWindow:
        final winW = size.width - 6;
        final winH = size.height * 0.58;
        final winRect = Rect.fromLTWH(3, (size.height - winH) / 2, winW, winH);
        canvas.drawRect(winRect, framePaint);
        canvas.drawRect(winRect, frameBorderPaint);
        const sashPad = 3.2;
        final sashRect = winRect.deflate(sashPad);
        canvas.drawRect(sashRect, sashFillPaint);
        canvas.drawRect(sashRect, sashBorderPaint);
        final glassRect = sashRect.deflate(2.8);
        drawGlass(glassRect);
        canvas.drawRect(glassRect, sashBorderPaint);
        drawTopOpenTriangle(sashRect);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(sashRect.center.dx, sashRect.top + 2.5),
            width: 5,
            height: 2,
          ),
          Paint()..color = handleColor,
        );
        break;

      case WindowPresetType.windowNoShutter:
        final winRect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
        canvas.drawRect(winRect, framePaint);
        canvas.drawRect(winRect, frameBorderPaint);
        const sashPad = 3.2;
        final innerRect = winRect.deflate(sashPad);
        final leafW = innerRect.width / 2;
        final leftSash = Rect.fromLTWH(
          innerRect.left,
          innerRect.top,
          leafW - 0.5,
          innerRect.height,
        );
        canvas.drawRect(leftSash, sashFillPaint);
        canvas.drawRect(leftSash, sashBorderPaint);
        final leftGlass = leftSash.deflate(2.8);
        drawGlass(leftGlass);
        canvas.drawRect(leftGlass, sashBorderPaint);
        drawOpenTriangles(leftSash, hingesLeft: true);
        final rightSash = Rect.fromLTWH(
          innerRect.left + leafW + 0.5,
          innerRect.top,
          leafW - 0.5,
          innerRect.height,
        );
        canvas.drawRect(rightSash, sashFillPaint);
        canvas.drawRect(rightSash, sashBorderPaint);
        final rightGlass = rightSash.deflate(2.8);
        drawGlass(rightGlass);
        canvas.drawRect(rightGlass, sashBorderPaint);
        drawOpenTriangles(rightSash, hingesLeft: false);
        canvas.drawCircle(
          Offset(leftSash.right, innerRect.center.dy),
          1.8,
          Paint()..color = handleColor,
        );
        break;

      case WindowPresetType.windowWithShutter:
        final boxH = size.height * 0.28;
        final boxRect = Rect.fromLTWH(2, 2, size.width - 4, boxH);
        drawShutterBox(boxRect);
        final winRect = Rect.fromLTWH(
          2,
          boxRect.bottom,
          size.width - 4,
          size.height - boxRect.bottom - 2,
        );
        canvas.drawRect(winRect, framePaint);
        canvas.drawRect(winRect, frameBorderPaint);
        const sashPad = 2.8;
        final innerRect = winRect.deflate(sashPad);
        final leafW = innerRect.width / 2;
        final leftSash = Rect.fromLTWH(
          innerRect.left,
          innerRect.top,
          leafW - 0.5,
          innerRect.height,
        );
        canvas.drawRect(leftSash, sashFillPaint);
        canvas.drawRect(leftSash, sashBorderPaint);
        final leftGlass = leftSash.deflate(2.4);
        drawGlass(leftGlass);
        canvas.drawRect(leftGlass, sashBorderPaint);
        drawOpenTriangles(leftSash, hingesLeft: true);
        final rightSash = Rect.fromLTWH(
          innerRect.left + leafW + 0.5,
          innerRect.top,
          leafW - 0.5,
          innerRect.height,
        );
        canvas.drawRect(rightSash, sashFillPaint);
        canvas.drawRect(rightSash, sashBorderPaint);
        final rightGlass = rightSash.deflate(2.4);
        drawGlass(rightGlass);
        canvas.drawRect(rightGlass, sashBorderPaint);
        drawOpenTriangles(rightSash, hingesLeft: false);
        break;

      case WindowPresetType.slidingNoShutter:
        final winRect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
        canvas.drawRect(winRect, framePaint);
        canvas.drawRect(winRect, frameBorderPaint);
        const sashPad = 3.2;
        final innerRect = winRect.deflate(sashPad);
        const overlap = 4.0;
        final sashW = (innerRect.width + overlap) / 2;
        final leftSash = Rect.fromLTWH(
          innerRect.left,
          innerRect.top,
          sashW,
          innerRect.height,
        );
        canvas.drawRect(leftSash, sashFillPaint);
        canvas.drawRect(leftSash, sashBorderPaint);
        final leftGlass = leftSash.deflate(2.8);
        drawGlass(leftGlass);
        canvas.drawRect(leftGlass, sashBorderPaint);
        drawSlidingArrows(leftSash, isLeftSash: true);
        final rightSash = Rect.fromLTWH(
          innerRect.right - sashW,
          innerRect.top,
          sashW,
          innerRect.height,
        );
        canvas.drawRect(rightSash, sashFillPaint);
        canvas.drawRect(rightSash, sashBorderPaint);
        final rightGlass = rightSash.deflate(2.8);
        drawGlass(rightGlass);
        canvas.drawRect(rightGlass, sashBorderPaint);
        drawSlidingArrows(rightSash, isLeftSash: false);
        canvas.drawLine(
          Offset(leftSash.right, innerRect.top),
          Offset(leftSash.right, innerRect.bottom),
          sashBorderPaint,
        );
        break;

      case WindowPresetType.slidingWithShutter:
        final boxH = size.height * 0.28;
        final boxRect = Rect.fromLTWH(2, 2, size.width - 4, boxH);
        drawShutterBox(boxRect);
        final winRect = Rect.fromLTWH(
          2,
          boxRect.bottom,
          size.width - 4,
          size.height - boxRect.bottom - 2,
        );
        canvas.drawRect(winRect, framePaint);
        canvas.drawRect(winRect, frameBorderPaint);
        const sashPad = 2.8;
        final innerRect = winRect.deflate(sashPad);
        const overlap = 4.0;
        final sashW = (innerRect.width + overlap) / 2;
        final leftSash = Rect.fromLTWH(
          innerRect.left,
          innerRect.top,
          sashW,
          innerRect.height,
        );
        canvas.drawRect(leftSash, sashFillPaint);
        canvas.drawRect(leftSash, sashBorderPaint);
        final leftGlass = leftSash.deflate(2.4);
        drawGlass(leftGlass);
        canvas.drawRect(leftGlass, sashBorderPaint);
        drawSlidingArrows(leftSash, isLeftSash: true);
        final rightSash = Rect.fromLTWH(
          innerRect.right - sashW,
          innerRect.top,
          sashW,
          innerRect.height,
        );
        canvas.drawRect(rightSash, sashFillPaint);
        canvas.drawRect(rightSash, sashBorderPaint);
        final rightGlass = rightSash.deflate(2.4);
        drawGlass(rightGlass);
        canvas.drawRect(rightGlass, sashBorderPaint);
        drawSlidingArrows(rightSash, isLeftSash: false);
        canvas.drawLine(
          Offset(leftSash.right, innerRect.top),
          Offset(leftSash.right, innerRect.bottom),
          sashBorderPaint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PresetThumbnailPainter oldDelegate) {
    return oldDelegate.preset != preset ||
        oldDelegate.isDark != isDark ||
        oldDelegate.accentColor != accentColor;
  }
}

class _CachedProfiles {
  final List<Map<String, dynamic>> frames;
  final List<Map<String, dynamic>> openingFrames;
  final List<Map<String, dynamic>> slidingFrames;
  final List<Map<String, dynamic>> sashes;
  final List<Map<String, dynamic>> openingSashes;
  final List<Map<String, dynamic>> slidingSashes;
  final Set<int> lateralIds;
  final Set<int> centralIds;

  const _CachedProfiles({
    required this.frames,
    required this.openingFrames,
    required this.slidingFrames,
    required this.sashes,
    required this.openingSashes,
    required this.slidingSashes,
    required this.lateralIds,
    required this.centralIds,
  });
}
