// Force compile sync trigger
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter,
        HardwareKeyboard,
        KeyEvent,
        KeyDownEvent;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/settings/shortcut_bindings.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/Commande/Systeme/model.dart'
    hide getComponentSize;
import 'package:database_data/Commande/Systeme/material_consumption_screen.dart';
import 'profile_selector_dialog.dart' hide getComponentSize;
import 'glass_joint_fit.dart';
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

class _DecorPlacementResult {
  final bool allowed;
  final String? cellId;

  const _DecorPlacementResult(this.allowed, this.cellId);
}

class _WindowViewState extends State<WindowView> {
  bool _drawingShortcut(KeyEvent event) {
    if (!mounted ||
        !_isWindowsDesktop ||
        event is! KeyDownEvent ||
        ModalRoute.of(context)?.isCurrent != true)
      return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null ||
        (focus.widget is EditableText) ||
        focus.findAncestorWidgetOfExactType<EditableText>() != null)
      return false;
    var belongsToDrawing = false;
    focus.visitAncestorElements((element) {
      if (element == context) belongsToDrawing = true;
      return !belongsToDrawing;
    });
    if (!belongsToDrawing ||
        !ShortcutBindings.instance.matches('drawing_mode', event))
      return false;
    _toggleDrawingInteractionMode();
    return false;
  }

  Widget _slidingGlassFitInfo(GlassSpecification spec) {
    final series = widget.model.effectiveSlidingSeries;
    final capacity = widget.model.glazingCapacityForStructure(
      spec.structure,
      sliding: true,
    );
    if (series == null ||
        capacity == null ||
        spec.structure == GlassStructure.closed)
      return const SizedBox.shrink();
    final glass = spec.totalThickness(widget.model.allGlassCache);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CatalogCandidateResolver(database: SqlDatabase()).resolve(
        CatalogCandidateQuery(
          category: 'joint',
          selectorType: 'joint_bourrage',
          roleKeys: const ['joint_bourrage'],
          seriesId: series.id,
          materialType: widget.model.isSlidingPVC ? 'pvc' : 'aluminium',
          drawingMode: AccessoryDrawingMode.sliding,
          requireDialog: false,
          requireQuantity: true,
          hasSimpleGlassForReducer: spec.structure == GlassStructure.simple,
          hasDoubleGlassForRules: spec.structure == GlassStructure.double,
        ),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final fit = findGlassJointFit(
          candidates: snapshot.data!,
          glassThickness: glass,
          capacity: capacity,
          sides: spec.jointTwoSides ? 2 : 1,
        );
        final message = fit == null
            ? 'تنبيه: لا توجد تركيبة جوانات مفعّلة تطابق الزجاج ($glass مم) والسعة ($capacity مم). النقص ممنوع والزيادة القصوى 1 مم.'
            : 'تركيبة جوانات متوافقة مقترحة: ${fit.map((row) => '${row['name']} (${row['thickness']} مم)').join(' + ')}. الزجاج: $glass مم، السعة: $capacity مم، الزيادة القصوى 1 مم دون نقص.';
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            message,
            style: TextStyle(
              fontSize: 11,
              color: fit == null ? Colors.red : Colors.green,
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>>? _handleCandidates;
  int? _handleSeriesId;

  Widget _buildRuleHandles(WindowZone zone) {
    final seriesId = widget.model.effectiveSlidingSeries?.id;
    if (_handleCandidates == null || _handleSeriesId != seriesId) {
      _handleSeriesId = seriesId;
      _handleCandidates = seriesId == null
          ? Future.value(<Map<String, dynamic>>[])
          : CatalogCandidateResolver(database: SqlDatabase()).resolve(
              CatalogCandidateQuery(
                category: 'accessory',
                selectorType: '',
                roleKeys: const ['handle', 'entrematique'],
                seriesId: seriesId,
                materialType: widget.model.isSlidingPVC ? 'pvc' : 'aluminium',
                drawingMode: AccessoryDrawingMode.sliding,
                requireDialog: true,
                requireQuantity: true,
              ),
            );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _handleCandidates,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('تعذر تحميل قواعد المقابض');
        if (!snapshot.hasData)
          return const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(),
          );
        final candidates = snapshot.data!.where((candidate) {
          final rule = candidate['catalog_rule'];
          return rule is Map &&
              rule['show_in_drawing'] != 0 &&
              rule['show_in_drawing'] != false;
        }).toList();
        if (candidates.isEmpty)
          return const Text('لا توجد مقابض مفعّلة لهذه السلسلة');
        final handleButtons = Wrap(
          spacing: 8,
          children: candidates.map((candidate) {
            final rule = candidate['catalog_rule'] as Map;
            final classic = rule['role_key'] != 'entrematique';
            final key = classic
                ? (widget.model.isSlidingPVC
                      ? 'مقبض نافذة (Poignée Fenêtre)'
                      : 'مقبض منزلق (Poignée Coulissante)')
                : 'أونتروماتيك (Entrematique)';
            return _ContentButton(
              label: '${candidate['name'] ?? candidate['code'] ?? ''}',
              icon: Icons.sync_alt_rounded,
              selected:
                  zone.useClassicHandle == classic &&
                  widget.model.componentOverrides[key]?['id'] ==
                      candidate['id'],
              onPressed: () {
                widget.model.componentOverrides[key] =
                    Map<String, dynamic>.from(candidate);
                widget.model.setSelectedZoneHandle(useClassicHandle: classic);
                setState(() {});
              },
            );
          }).toList(),
        );
        if (zone.slidingSashesCount < 4 || zone.slidingSashesCount % 2 != 0) {
          return handleButtons;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            handleButtons,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (widget.model.supportsSlidingFaceToFace)
                  _ContentButton(
                    label: 'التقاء الوسط (Face-to-Face)',
                    icon: Icons.layers_rounded,
                    selected: zone.slidingFaceToFace,
                    onPressed: () {
                      widget.model.toggleSelectedZoneSlidingFaceToFace();
                      setState(() {});
                    },
                  ),
                if (zone.slidingFaceToFace ||
                    (zone.slidingSashesCount == 6 &&
                        zone.slidingTrackCount == 3)) ...[
                  _ContentButton(
                    label: 'مقبض وسط الضلفتين',
                    icon: Icons.more_horiz_rounded,
                    selected: zone.slidingCentralHandle,
                    onPressed: () {
                      widget.model.toggleSelectedZoneSlidingCentralHandle();
                      setState(() {});
                    },
                  ),
                  _ContentButton(
                    label: 'مقبض الوسط الثاني (شكلي)',
                    icon: Icons.more_horiz_outlined,
                    selected: zone.slidingSecondCentralHandle,
                    onPressed: () {
                      if (!zone.slidingCentralHandle) return;
                      widget.model
                          .toggleSelectedZoneSlidingSecondCentralHandle();
                      setState(() {});
                    },
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  static const double _minUserScale = 0.5;
  static const double _maxUserScale = 5.0;
  static const double _zoomStep = 1.15;

  String _tr(String key) =>
      Localization.translate(key, context.read<AppSettingsProvider>().language);

  String _trackCountLabel(int count, AppLanguage lang) => switch (lang) {
    AppLanguage.arabic => '$count سكك',
    AppLanguage.french => '$count rails',
    AppLanguage.english => '$count tracks',
  };

  String _trackTitle(AppLanguage lang) => switch (lang) {
    AppLanguage.arabic => 'عدد السكك في الإطار:',
    AppLanguage.french => 'Nombre de rails du cadre :',
    AppLanguage.english => 'Frame track count:',
  };

  String _trackShortTitle(AppLanguage lang) => switch (lang) {
    AppLanguage.arabic => 'السكك:',
    AppLanguage.french => 'Rails :',
    AppLanguage.english => 'Tracks:',
  };

  String _slidingCountLabel(int count, AppLanguage lang) => switch (lang) {
    AppLanguage.arabic => 'منزلق $count',
    AppLanguage.french => 'Coulissant $count vantaux',
    AppLanguage.english => '$count-sash sliding',
  };

  String _frameTrackCompositionLabel(
    int trackCount,
    bool complete,
    AppLanguage lang,
  ) {
    if (complete) {
      return switch (lang) {
        AppLanguage.arabic => 'إطار كامل بـ $trackCount سكك',
        AppLanguage.french => 'Cadre complet à $trackCount rails',
        AppLanguage.english => 'Complete $trackCount-track frame',
      };
    }
    if (trackCount <= 2) {
      return switch (lang) {
        AppLanguage.arabic => 'إطار أساسي بسكتين',
        AppLanguage.french => 'Cadre de base à 2 rails',
        AppLanguage.english => 'Two-track base frame',
      };
    }
    final additions = trackCount - 2;
    return switch (lang) {
      AppLanguage.arabic => 'إطار أساسي بسكتين + $additions سكة إضافية',
      AppLanguage.french =>
        'Cadre de base à 2 rails + $additions rail(s) ajouté(s)',
      AppLanguage.english =>
        'Two-track base frame + $additions additional track(s)',
    };
  }

  bool _seriesMatchesScope(
    AluminumSeries series,
    AluminumProfileSystem system,
    String scope,
  ) {
    return widget.model.seriesSupportsDrawingScopeInSystem(
      series,
      scope,
      profile: system,
    );
  }

  List<AluminumSeries> _seriesForScope(
    AluminumProfileSystem system,
    String scope,
  ) {
    final normalizedScope = scope.trim().toLowerCase();
    final oppositeScope = normalizedScope == 'sliding' ? 'opening' : 'sliding';
    final matching = system.series
        .where((series) => _seriesMatchesScope(series, system, normalizedScope))
        .toList();

    if (matching.isNotEmpty) {
      // A system can contain several opening/sliding series. Older catalogues
      // often configured the drawing roles for only one series, so returning
      // `matching` alone hides the other active series from the selector.
      // Broaden the result within this exact system, while still excluding a
      // series that is explicitly classified for the opposite drawing.
      final broadened = system.series.where((series) {
        if (_seriesMatchesScope(series, system, normalizedScope)) return true;
        // Check the opposite scope only on the series itself. Using the
        // system-wide fallback here would classify an unlabelled series as
        // both families and then remove it from this list again.
        if (widget.model.seriesSupportsDrawingScope(
          series,
          oppositeScope,
          profile: system,
        )) {
          return false;
        }
        return normalizedScope == 'sliding'
            ? !isOpeningSeriesForDrawing(series, system)
            : !isSlidingSeriesForDrawing(series);
      }).toList();
      if (broadened.isNotEmpty) return broadened;
    }

    // Some imported catalogues contain a valid multi-series system but do
    // not label the series with an opening/sliding keyword or scope. Keep
    // those active series selectable instead of hiding the whole system,
    // while never putting an explicitly sliding series in the opening list.
    final directlySliding = system.series
        .where(
          (series) => widget.model.seriesSupportsDrawingScope(
            series,
            'sliding',
            profile: system,
          ),
        )
        .toList();
    final directlyOpening = system.series
        .where(
          (series) => widget.model.seriesSupportsDrawingScope(
            series,
            'opening',
            profile: system,
          ),
        )
        .toList();

    if (normalizedScope == 'opening') {
      final unclassified = system.series
          .where((series) => !directlySliding.any((s) => s.id == series.id))
          .toList();
      if (unclassified.isNotEmpty) return unclassified;
      return directlyOpening;
    }
    if (directlyOpening.isNotEmpty) {
      return const <AluminumSeries>[];
    }
    return List<AluminumSeries>.from(system.series);
  }

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get isSlidingSupported {
    if (widget.systemMode == 'mixed') {
      final system = profileSystemForSeries(
        widget.model.availableSystems,
        widget.model.activeSeries ?? widget.model.activeSlidingSeries,
      );
      return system != null && _seriesForScope(system, 'sliding').isNotEmpty;
    }

    if (widget.systemMode != 'sliding') return false;
    final series = widget.model.activeSlidingSeries;
    if (series == null) return false;
    final system = profileSystemForSeries(
      widget.model.availableSystems,
      series,
    );
    return system != null && _seriesForScope(system, 'sliding').isNotEmpty;
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
  bool _suppressHandleDragForLongPress = false;
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
  bool _isExitDialogOpen = false;

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
  bool _slidingSeriesAutoSelectionQueued = false;
  bool _openingSeriesAutoSelectionQueued = false;

  // Drawing actions can generate far more pointer events than the display can
  // render.  Keep the full controls page at one refresh per frame; the canvas
  // itself listens to the model and remains immediate.
  bool _modelUiRefreshQueued = false;

  bool _isCaissonTunnelOption(Map<String, dynamic> option) {
    final name = (option['name'] ?? '').toString().toLowerCase();
    final type = (option['component_type'] ?? '').toString().toLowerCase();
    return name.contains('tunnel') ||
        name.contains('نفق') ||
        type.contains('tunnel') ||
        type.contains('نفق');
  }

  double? _caissonSizeMm(Map<String, dynamic> option) {
    final raw = getComponentSize(option);
    if (raw == null || raw.trim().isEmpty) return null;
    var size = double.tryParse(raw.replaceAll(',', '.'));
    if (size == null || size <= 0) return null;
    if (size < 100) size *= 10;
    return size;
  }

  Future<void> _loadAvailableProfiles() async {
    final requestGeneration = ++_profileLoadGeneration;
    final seriesId = activeSeriesForSystem?.id;
    if (seriesId == null) {
      if (mounted) {
        setState(() {
          _frameProfiles = [];
          _openingFrameProfiles = [];
          _slidingFrameProfiles = [];
          _sashProfiles = [];
          _openingSashProfiles = [];
          _slidingSashProfiles = [];
          _slidingLateralProfileIds = {};
          _slidingCentralProfileIds = {};
          _loadedSeriesId = null;
          _loadedOpeningFrameSeriesId = null;
          _loadedSlidingFrameSeriesId = null;
        });
      }
      return;
    }
    final openingSeriesId = widget.model.activeSeries?.id;
    final slidingSeriesId = widget.model.activeSlidingSeries?.id;
    final needsOpeningFrames =
        widget.systemMode == 'mixed' && openingSeriesId != null;
    final needsSlidingFrames =
        (widget.systemMode == 'mixed' || widget.systemMode == 'sliding') &&
        slidingSeriesId != null;
    if (_loadedSeriesId == seriesId &&
        (!needsOpeningFrames ||
            _loadedOpeningFrameSeriesId == openingSeriesId) &&
        (!needsSlidingFrames ||
            _loadedSlidingFrameSeriesId == slidingSeriesId)) {
      return;
    }
    if (_loadingAvailableProfiles) return;
    _loadingAvailableProfiles = true;
    try {
      final db = SqlDatabase();
      final myDb = await db.db;
      if (myDb == null) return;

      final primaryUsesSlidingFrames =
          widget.systemMode == 'sliding' ||
          (widget.systemMode == 'mixed' &&
              seriesId == slidingSeriesId &&
              seriesId != openingSeriesId);
      final frames = await _loadFrameProfilesForSeries(
        db,
        seriesId,
        sliding: primaryUsesSlidingFrames,
      );
      final sashes = await _loadSashProfilesForSeries(
        db,
        seriesId,
        sliding: primaryUsesSlidingFrames,
      );
      final openingFrames = needsOpeningFrames
          ? await _loadFrameProfilesForSeries(
              db,
              openingSeriesId,
              sliding: false,
            )
          : <Map<String, dynamic>>[];
      final slidingFrames = needsSlidingFrames
          ? await _loadFrameProfilesForSeries(
              db,
              slidingSeriesId,
              sliding: true,
            )
          : <Map<String, dynamic>>[];
      final openingSashes = needsOpeningFrames
          ? await _loadSashProfilesForSeries(
              db,
              openingSeriesId,
              sliding: false,
            )
          : <Map<String, dynamic>>[];
      final slidingSashes = needsSlidingFrames
          ? await _loadSashProfilesForSeries(db, slidingSeriesId, sliding: true)
          : <Map<String, dynamic>>[];
      final montantRoleSeriesId = slidingSeriesId ?? seriesId;
      final lateralRoleProfiles = await db.getDesignSectionsForDrawingRoles(
        montantRoleSeriesId,
        const ['sash_lateral', 'lateral'],
        usageScope: 'sliding',
      );
      final centralRoleProfiles = await db
          .getDesignSectionsForDrawingRoles(montantRoleSeriesId, const [
            'sash_central',
            'central',
            'chicane',
            'chicane_renforcee',
            'sash_central_reinforced',
          ], usageScope: 'sliding');

      // Ignore an old result when either series changed. Publishing only one
      // complete generation prevents opening and sliding rows from being
      // mixed while the two selectors are changing quickly.
      if (!mounted ||
          requestGeneration != _profileLoadGeneration ||
          activeSeriesForSystem?.id != seriesId ||
          widget.model.activeSeries?.id != openingSeriesId ||
          widget.model.activeSlidingSeries?.id != slidingSeriesId) {
        return;
      }
      Set<int> idsFrom(List<Map<String, dynamic>> rows) => rows
          .map((row) {
            final rawId = row['id'];
            return rawId is num
                ? rawId.toInt()
                : int.tryParse('${rawId ?? ''}');
          })
          .whereType<int>()
          .toSet();
      setState(() {
        _frameProfiles = frames;
        _openingFrameProfiles = openingFrames;
        _slidingFrameProfiles = slidingFrames;
        _sashProfiles = sashes;
        _openingSashProfiles = openingSashes;
        _slidingSashProfiles = slidingSashes;
        _slidingLateralProfileIds = idsFrom(lateralRoleProfiles);
        _slidingCentralProfileIds = idsFrom(centralRoleProfiles);
        _loadedSeriesId = seriesId;
        _loadedOpeningFrameSeriesId = needsOpeningFrames
            ? openingSeriesId
            : null;
        _loadedSlidingFrameSeriesId = needsSlidingFrames
            ? slidingSeriesId
            : null;
      });
    } finally {
      _loadingAvailableProfiles = false;
      // Only queue another load when the user changed the series while this
      // request was in flight. Retrying the same failed request in a tight
      // loop would make the drawing page appear to crash temporarily.
      if (mounted && activeSeriesForSystem?.id != null) {
        final currentOpeningSeriesId = widget.model.activeSeries?.id;
        final currentSlidingSeriesId = widget.model.activeSlidingSeries?.id;
        final currentNeedsOpeningFrames =
            widget.systemMode == 'mixed' && currentOpeningSeriesId != null;
        final currentNeedsSlidingFrames =
            (widget.systemMode == 'mixed' || widget.systemMode == 'sliding') &&
            currentSlidingSeriesId != null;
        final profilesChangedWhileLoading =
            requestGeneration != _profileLoadGeneration ||
            activeSeriesForSystem?.id != seriesId ||
            widget.model.activeSeries?.id != openingSeriesId ||
            widget.model.activeSlidingSeries?.id != slidingSeriesId ||
            (currentNeedsOpeningFrames &&
                currentOpeningSeriesId != openingSeriesId) ||
            (currentNeedsSlidingFrames &&
                currentSlidingSeriesId != slidingSeriesId);
        if (profilesChangedWhileLoading) {
          unawaited(_loadAvailableProfiles());
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadFrameProfilesForSeries(
    SqlDatabase db,
    int seriesId, {
    required bool sliding,
  }) async {
    // SeriesDesignRoles is the only source for profiles on the drawing page.
    return db.getDesignSectionsForDrawingRoles(
      seriesId,
      sliding ? const ['frame', 'frame_extension'] : const ['frame'],
      usageScope: sliding ? 'sliding' : 'opening',
    );
  }

  Future<List<Map<String, dynamic>>> _loadSashProfilesForSeries(
    SqlDatabase db,
    int seriesId, {
    required bool sliding,
  }) async {
    return db.getDesignSectionsForDrawingRoles(
      seriesId,
      sliding
          ? const [
              'sash',
              'sash_extension',
              'sash_lateral',
              'sash_lateral_reinforced',
              'sash_central',
              'sash_central_reinforced',
              'sash_traverse',
              'chicane',
              'chicane_renforcee',
            ]
          : const ['sash', 'sash_extension'],
      usageScope: sliding ? 'sliding' : 'opening',
    );
  }

  bool _seriesIsPvc(AluminumSeries? series) {
    if (series == null) return widget.model.isPVC;
    for (final system in widget.model.availableSystems) {
      if (system.id == series.profileId ||
          system.series.any((candidate) => candidate.id == series.id)) {
        return system.type.toLowerCase().trim() == 'pvc';
      }
    }
    return false;
  }

  /// PVC has no reinforced sliding montant. Keep this rule at the drawing
  /// level so an old saved flag cannot bring reinforcement controls back.
  bool get _pvcMontantReinforcementDisabled =>
      widget.model.isPVC ||
      widget.model.isSlidingPVC ||
      _seriesIsPvc(widget.model.activeSlidingSeries);

  List<Map<String, dynamic>> _filterFrameProfilesForDrawingRules(
    List<Map<String, dynamic>> profiles, {
    required AluminumSeries? series,
    AccessoryDrawingMode? drawingMode,
  }) {
    // The rows have already been resolved from the exact series role. Do not
    // classify them again from commercial names such as TPR/HPS: that old
    // heuristic was able to put opening frames in the sliding picker.
    var filtered = profiles.toList();
    final isMultiFrame = widget.model.getFrameRects().length > 1;
    if (isMultiFrame) {
      return filtered
          .where((profile) => !profileHasIntegratedSideCover(profile))
          .toList();
    }
    if (!widget.model.hasShutter ||
        widget.model.isCaissonTunnel ||
        _seriesIsPvc(series)) {
      return filtered;
    }
    return filtered
        .where((profile) => !profileHasIntegratedSideCover(profile))
        .toList();
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
      final amountToReveal = updatedPosition.extentAfter
          .clamp(0.0, 96.0)
          .toDouble();
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

  Future<bool?> _askSlidingRebateCut(WindowZone zone) async {
    if (!widget.model.shouldAskSlidingRebateCut(zone)) return null;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Localization.translate('ركوب الزجاج للمنزلق', lang)),
        content: Text(
          Localization.translate(
            'هذا المنزلق داخل إطار واحد مقسم. هل سيتم قطع وحساب ركوب الزجاج حول منطقة المنزلق؟',
            lang,
          ),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(Localization.translate('لا', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(Localization.translate('نعم', lang)),
          ),
        ],
      ),
    );
  }

  void _showSlidingUnsupportedSnack() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
  }

  Future<void> _setSelectedZoneSlidingSashesFromUi(int count) async {
    final zone = widget.model.selectedZone;
    if (zone == null) return;
    if (widget.model.hasArchOrSlant) {
      _showSlidingUnsupportedSnack();
      return;
    }
    final cutRebate = await _askSlidingRebateCut(zone);
    if (!mounted) return;
    setState(() {
      widget.model.setSelectedZoneSlidingSashes(
        count,
        cutSlidingGlassRebate: cutRebate,
      );
    });
  }

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

  double _catalogNumber(Map<String, dynamic> row, String key) {
    final value = row[key];
    return value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  bool _isDecorPanelSpec(GlassSpecification spec) {
    return spec.structure == GlassStructure.closed &&
        (isDecorPanelSubtype(spec.panneauSubtype) ||
            spec.finishOuter == GlassFinish.paneauSandwitchDecore);
  }

  Size _decorPanelFullSpace(WindowZone zone, String? cellId) {
    Rect target = zone.boundary;
    final isDouble = zone.content == ZoneContent.doubleSash;
    final isSash =
        isDouble ||
        zone.content == ZoneContent.singleSash ||
        zone.content == ZoneContent.slidingSash;

    if (isDouble) {
      final splitX =
          zone.boundary.left + zone.boundary.width * zone.doubleSashRatio;
      const separator = 4.0;
      target = (cellId ?? '').startsWith('right')
          ? Rect.fromLTRB(
              splitX + separator / 2,
              zone.boundary.top,
              zone.boundary.right,
              zone.boundary.bottom,
            )
          : Rect.fromLTRB(
              zone.boundary.left,
              zone.boundary.top,
              splitX - separator / 2,
              zone.boundary.bottom,
            );
    } else if (zone.content == ZoneContent.slidingSash) {
      final count = math.max(1, zone.slidingSashesCount);
      target = Rect.fromLTWH(
        zone.boundary.left,
        zone.boundary.top,
        zone.boundary.width / count,
        zone.boundary.height,
      );
    }

    if (isSash) {
      final sashThickness =
          zone.sashThickness ??
          widget.model.getSectionThickness('sash', fallback: 45.0);
      final width = math.max(0.0, target.width - 2 * sashThickness);
      final height = math.max(0.0, target.height - 2 * sashThickness);
      return Size(width, height);
    }
    return Size(math.max(0.0, target.width), math.max(0.0, target.height));
  }

  bool _decorPanelSideHasDivisions(WindowZone zone, String? cellId) {
    final key = cellId ?? '';
    final hasLeftOrMain =
        zone.innerH > 0 ||
        zone.innerV > 0 ||
        zone.innerHPositions.isNotEmpty ||
        zone.innerVPositions.isNotEmpty;
    final hasRight =
        zone.rightInnerH > 0 ||
        zone.rightInnerV > 0 ||
        zone.rightInnerHPositions.isNotEmpty ||
        zone.rightInnerVPositions.isNotEmpty;
    if (key.startsWith('right')) return hasRight;
    if (key.startsWith('left') || key.startsWith('main')) {
      return hasLeftOrMain;
    }
    return hasLeftOrMain || hasRight;
  }

  Future<_DecorPlacementResult> _prepareDecorPanelPlacement({
    required WindowZone zone,
    required String? cellId,
    required GlassSpecification spec,
  }) async {
    if (!_isDecorPanelSpec(spec)) {
      return _DecorPlacementResult(true, cellId);
    }

    final product = widget.model.getPanneauProductForSpec(spec);
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final decorWidth = product == null
        ? 0.0
        : _catalogNumber(product, 'visible_width');
    final decorHeight = product == null
        ? 0.0
        : _catalogNumber(product, 'height');
    if (product == null || decorWidth <= 0 || decorHeight <= 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            Localization.translate('أبعاد البانو ديكور غير محددة', lang),
          ),
          content: Text(
            Localization.translate(
              'يجب تحديد عرض الديكور وطوله في منتج الزجاج أولاً.',
              lang,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('حسناً', lang)),
            ),
          ],
        ),
      );
      return _DecorPlacementResult(false, cellId);
    }

    final available = _decorPanelFullSpace(zone, cellId);
    if (!decorPanelFitsSpace(
      spaceWidth: available.width,
      spaceHeight: available.height,
      decorWidth: decorWidth,
      decorHeight: decorHeight,
    )) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            Localization.translate('لا يمكن وضع هذا البانو هنا', lang),
          ),
          content: Text(
            '${Localization.translate('حجم الديكور', lang)} ${decorWidth.toStringAsFixed(0)} × ${decorHeight.toStringAsFixed(0)} ${Localization.translate('مم', lang)} '
            '${Localization.translate('أكبر من المساحة المتاحة', lang)} ${available.width.toStringAsFixed(0)} × ${available.height.toStringAsFixed(0)} ${Localization.translate('مم', lang)}. '
            '${Localization.translate('ينبغي اختيار بانو آخر.', lang)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('حسناً', lang)),
            ),
          ],
        ),
      );
      return _DecorPlacementResult(false, cellId);
    }

    if (!_decorPanelSideHasDivisions(zone, cellId)) {
      return _DecorPlacementResult(true, cellId);
    }

    final removeDivisions = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Localization.translate('إلغاء التقسيم؟', lang)),
        content: Text(
          '${Localization.translate('البانو ديكور لا يقبل أي تقسيمات.', lang)} '
          '${Localization.translate('يجب إلغاء التقسيم الحالي لتفعيله. هل توافق؟', lang)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(Localization.translate('لا', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(Localization.translate('نعم', lang)),
          ),
        ],
      ),
    );
    if (removeDivisions != true) {
      return _DecorPlacementResult(false, cellId);
    }

    final normalizedCell = widget.model.removeSashDivisions(
      zoneOverride: zone,
      targetCellKey: cellId,
    );
    return _DecorPlacementResult(true, normalizedCell);
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

  String _currentSelectionKey() {
    final selection = widget.model.selection;
    return '${selection.type}|${selection.zoneId}|${selection.mullionPosition}|'
        '${selection.innerDivisionIndex}|${widget.model.activeSubZone ?? ''}';
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
        if (!wasExpanded) _activeBottomTab = 0;
      }
      _previousSelectionKey = currentSelectionKey;
    }

    // The preview has its own repaint listener.  While drawing a new frame,
    // rebuilding the drawers and all their controls on every mouse movement
    // is unnecessary and was the main source of lag on Windows.
    if (widget.model.drawingStart != null && !selectionChanged) {
      return;
    }

    if (selectionChanged) {
      _refreshModelDependentUi();
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

  void _queueMixedSlidingSeriesSelection(
    AluminumSeries candidate,
    int? openingSeriesId,
  ) {
    if (_slidingSeriesAutoSelectionQueued) return;
    _slidingSeriesAutoSelectionQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted ||
            widget.model.activeSeries?.id != openingSeriesId ||
            widget.model.activeSlidingSeries != null ||
            widget.model.activeSlidingSeries?.id == candidate.id) {
          return;
        }
        widget.model.systemMode = 'mixed';
        await widget.model.setActiveSlidingSeries(candidate);
      } finally {
        _slidingSeriesAutoSelectionQueued = false;
      }
    });
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
            "LOWER(TRIM(component_type)) IN ('blade', 'lame') AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'name ASC',
      );

      // السكك (Coulisses)
      final coulisses = await dbInstance.query(
        'ShutterComponents',
        where:
            "LOWER(TRIM(component_type)) IN ('track', 'coulisse', 'coulisses', 'glissiere') AND (is_active = 1 OR is_active IS NULL)",
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
      final shutterRules = seriesId == null
          ? <Map<String, dynamic>>[]
          : await db.getSeriesShutterRules(seriesId);

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

      // A box is selectable only when the limit configured for the current
      // blade on the price-management page accepts this window height.  The
      // same rule is used by the material calculation, so the visual choice
      // can never disagree with the required-goods table.
      final unavailableCaissonReasons = <int, String>{};
      Map<String, dynamic>? selectedBlade;
      final rawBlade = widget.model.componentOverrides['الشرائح (Lames)'];
      if (rawBlade is Map) {
        selectedBlade = Map<String, dynamic>.from(rawBlade);
      }
      if (selectedBlade == null) {
        for (final blade in configuredLames) {
          if (blade['name']?.toString() == widget.model.shutterLame) {
            selectedBlade = blade;
            break;
          }
        }
      }
      final bladeId = (selectedBlade?['id'] as num?)?.toInt();
      if (widget.model.hasShutter && bladeId != null) {
        final limits = await dbInstance.query(
          'ShutterBoxLimits',
          where: 'blade_id = ?',
          whereArgs: [bladeId],
        );
        final fallbackMinimumSize = widget.model.height > 2400
            ? 205.0
            : (widget.model.height > 1600 ? 185.0 : 155.0);
        if (limits.isNotEmpty) {
          for (final caisson in configuredCaissons) {
            if (_isCaissonTunnelOption(caisson)) continue;
            final id = (caisson['id'] as num?)?.toInt();
            final size = _caissonSizeMm(caisson);
            if (id == null || size == null) continue;
            final matchingLimits = limits.where((limit) {
              final limitSize = (limit['box_size'] as num?)?.toDouble() ?? 0;
              return (limitSize - size).abs() < 5;
            });
            final maxHeight = matchingLimits
                .map((limit) => (limit['max_height'] as num?)?.toDouble() ?? 0)
                .fold<double>(0, (max, value) => value > max ? value : max);
            if (maxHeight <= 0) {
              unavailableCaissonReasons[id] =
                  'هذا الصندوق غير مضبوط لهذه الشفرة في حدود الستار.';
            } else if (widget.model.height > maxHeight) {
              unavailableCaissonReasons[id] =
                  'الحد الأقصى لهذا الصندوق ${maxHeight.toStringAsFixed(0)} مم.';
            }
          }
        } else {
          for (final caisson in configuredCaissons) {
            if (_isCaissonTunnelOption(caisson)) continue;
            final id = (caisson['id'] as num?)?.toInt();
            final size = _caissonSizeMm(caisson);
            if (id == null || size == null) continue;
            if (size + 0.5 < fallbackMinimumSize) {
              unavailableCaissonReasons[id] =
                  'هذا الصندوق أصغر من الحد المطلوب ${fallbackMinimumSize.toStringAsFixed(0)} مم.';
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _shutterLamesOptions = configuredLames;
          _shutterCoulisseOptions = configuredCoulisses;
          _shutterCaissonOptions = configuredCaissons;
          _unavailableCaissonReasons = unavailableCaissonReasons;
          _loadingShutterOptions = false;
        });
      }
      if (widget.model.hasShutter) {
        unawaited(widget.model.updateShutterDefaultsIfNeeded());
      }
    } catch (e) {
      if (mounted) setState(() => _loadingShutterOptions = false);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_drawingShortcut);
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

    final hingeCount = standardHingeCountForSash(
      sashHeight: zone.boundary.height,
      glassStructure: zone.glass.structure,
    );

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
          math.min(widget.model.topSlantLeftY, widget.model.topSlantRightY) -
          (widget.model.archHeight * 2) +
          t;
      return (1.0 - factor) * (1.0 - factor) * yL +
          2.0 * (1.0 - factor) * factor * yC +
          factor * factor * yR;
    } else {
      return yL + factor * (yR - yL);
    }
  }

  double getSashTopY(
    double x,
    double sashTopFlat,
    double t,
    double topOffset,
    bool isTopBound,
  ) {
    if (!isTopBound) return sashTopFlat;
    double clearance = sashTopFlat - (topOffset + t);
    if (clearance < 0) clearance = 0;
    return getInnerTopY(x, t, topOffset) + clearance;
  }

  void _showMullionResizeDialog(BuildContext context, int section) {
    bool isH = widget.model.selection.isHorizontalMullion!;
    double pos = widget.model.selection.mullionPosition!;
    final t = widget.model.profileThickness;
    final sep = widget.model.mullionThickness / 2;
    final inset = t + sep;
    double currentValue = isH
        ? (section == 1 ? (pos - inset) : (widget.model.height - pos - inset))
        : (section == 1 ? (pos - inset) : (widget.model.width - pos - inset));
    final ctrl = TextEditingController(text: currentValue.toInt().toString());
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
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
            Localization.translate(label, lang),
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
              labelText: Localization.translate(
                'البُعد الصافي للفراغ (mm)',
                lang,
              ),
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
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(color: Colors.grey),
              ),
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
              child: Text(
                Localization.translate('تطبيق القياس الجديد', lang),
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _checkAndStartSashDividerDrag(
    String zoneId,
    bool isRight,
    Rect glassR,
    int innerH,
    int innerV,
    List<double> innerHPos,
    List<double> innerVPos,
    Offset touchScreen,
  ) {
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
    final zone = widget.model.zones.firstWhere(
      (candidate) => candidate.id == zoneId,
      orElse: () => WindowZone(
        id: zoneId,
        boundary: Rect.zero,
        sashColor: widget.model.frameColor,
      ),
    );
    String getVKey(int r, int v) => isRight ? 'right_${r}_$v' : '${r}_$v';
    String getHKey(int c, int h) => isRight ? 'right_${c}_$h' : '${c}_$h';

    // Check horizontal dividers
    for (int i = 0; i < hPositions.length; i++) {
      double yVal = glassR.top + glassR.height * hPositions[i];
      for (int c = 0; c < vPositions.length + 1; c++) {
        if (zone.disabledHorizontalDivisions[getHKey(c, i)] == true) {
          continue;
        }
        final leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
        final rightRatio = c == vPositions.length ? 1.0 : vPositions[c];
        final lineStart = _modelToScreen(
          Offset(glassR.left + glassR.width * leftRatio, yVal),
        );
        final lineEnd = _modelToScreen(
          Offset(glassR.left + glassR.width * rightRatio, yVal),
        );
        final screenY = lineStart.dy;
        final screenLeft = math.min(lineStart.dx, lineEnd.dx);
        final screenRight = math.max(lineStart.dx, lineEnd.dx);

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
    }

    // Check vertical dividers
    for (int i = 0; i < vPositions.length; i++) {
      double xVal = glassR.left + glassR.width * vPositions[i];
      for (int r = 0; r < hPositions.length + 1; r++) {
        if (zone.disabledVerticalDivisions[getVKey(r, i)] == true) {
          continue;
        }
        final topRatio = r == 0 ? 0.0 : hPositions[r - 1];
        final bottomRatio = r == hPositions.length ? 1.0 : hPositions[r];
        final lineStart = _modelToScreen(
          Offset(xVal, glassR.top + glassR.height * topRatio),
        );
        final lineEnd = _modelToScreen(
          Offset(xVal, glassR.top + glassR.height * bottomRatio),
        );
        final screenX = lineStart.dx;
        final screenTop = math.min(lineStart.dy, lineEnd.dy);
        final screenBottom = math.max(lineStart.dy, lineEnd.dy);

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
    }

    return false;
  }

  bool _checkAndStartGlassDecorDrag(
    String zoneId,
    Rect glassR,
    GlassSpecification spec,
    Offset touchScreen,
  ) {
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
    HardwareKeyboard.instance.addHandler(_drawingShortcut);
    // Any model opened through the full design workspace must return here
    // when it is edited, including designs that use a tunnel box or wall.
    widget.model.isDesignDrawing = true;
    _positionCtrl = TextEditingController(text: widget.model.position ?? '');
    widget.model.loadCatalogData(widget.systemMode);
    widget.model.addListener(_onModelChanged);
    _syncDrawerGlassFromDrawing();
    if (activeSeriesForSystem != null) {
      _loadAvailableProfiles();
    }
    _loadShutterOptions(); // Preload shutter options from database
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
      _userPan =
          focalPoint -
          canvasOrigin -
          (focalPoint - canvasOrigin - _userPan) * scaleRatio;
      _userScale = nextScale;
    });
  }

  void _handleDrawingPointerSignal(PointerSignalEvent event) {
    if (!_isWindowsDesktop || event is! PointerScrollEvent) return;
    final verticalDelta = event.scrollDelta.dy;
    if (verticalDelta == 0) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      _changeDrawingZoom(
        verticalDelta < 0 ? _zoomStep : 1 / _zoomStep,
        _drawingViewportCenter(),
      );
    });
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

  int? _frameAtBorder(Offset modelPosition) {
    final thickness = widget.model.profileThickness;
    final frameRects = widget.model.getFrameRects();
    for (var index = frameRects.length - 1; index >= 0; index--) {
      final outer = frameRects[index];
      final inner = outer.deflate(thickness * 0.72);
      if (outer.inflate(12.0).contains(modelPosition) &&
          !inner.deflate(8.0).contains(modelPosition)) {
        return index;
      }
    }
    return null;
  }

  _FrameResizeHandle? _frameResizeHandleAt(Offset screenPosition) {
    final frameKey =
        (widget.model.selection.type == SelectionType.frame ||
            widget.model.selection.type == SelectionType.zone)
        ? widget.model.selection.zoneId
        : null;
    final outer = widget.model.frameRectForSelection(frameKey);
    if (outer == null) return null;
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
    double closestDistance = 30.0;
    for (final entry in handles.entries) {
      final distance = (_modelToScreen(entry.value) - screenPosition).distance;
      if (distance <= closestDistance) {
        closest = entry.key;
        closestDistance = distance;
      }
    }
    return closest;
  }

  Rect? _dimensionTextBounds(
    String text,
    Rect bounds, {
    bool vertical = false,
  }) {
    final crossAxis = vertical ? bounds.width : bounds.height;
    final mainAxis = vertical ? bounds.height : bounds.width;
    if (crossAxis < 12 || mainAxis < 35) return null;

    double fontSize = math.min(34.0, math.max(15.0, crossAxis * 0.78));
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width <= mainAxis - 8 || fontSize <= 10) break;
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
    final frameRects = widget.model.getFrameRects();
    for (final outer in frameRects.reversed) {
      WindowZone? representativeZone;
      final inner = outer.deflate(thickness);
      for (final zone in widget.model.zones) {
        if (inner.overlaps(zone.boundary) ||
            inner.contains(zone.boundary.center)) {
          representativeZone = zone;
          break;
        }
      }
      if (representativeZone == null) continue;
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
          return InnerDimensionHit(representativeZone.id, true);
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
          return InnerDimensionHit(representativeZone.id, false);
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

  void _activateShutterFromDesign() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final hasMeasuredDrawing =
        widget.model.width > 0 && widget.model.height > 0;
    final convertingExistingDrawing =
        hasMeasuredDrawing && !widget.model.isShutterOnly;
    setState(() {
      if (convertingExistingDrawing) {
        widget.model.convertCurrentDrawingToShutter();
      } else if (!widget.model.isShutterOnly) {
        widget.model.prepareShutterOnlyDrawing();
      }
      _isShutterSelected = true;
      _isBottomPanelExpanded = true;
      _isDrawerOpen = false;
      _isLeftDrawerOpen = false;
      _activeShutterTab = 0;
    });

    if (_shutterLamesOptions.isEmpty && _shutterCoulisseOptions.isEmpty) {
      _loadShutterOptions();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localization.translate(
            convertingExistingDrawing
                ? 'تم تحويل القياس الحالي إلى ستار'
                : 'ارسم مستطيل الستار على اللوحة',
            lang,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<Widget> _buildWindowsAppBarDrawingControls(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        style: widget.model.isDrawingMode
            ? buttonStyle.copyWith(
                backgroundColor: WidgetStatePropertyAll(Colors.green.shade600),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              )
            : buttonStyle,
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
      TextButton.icon(
        style: buttonStyle,
        onPressed: _activateShutterFromDesign,
        icon: Icon(
          widget.model.hasShutter
              ? Icons.layers_rounded
              : Icons.add_box_rounded,
          size: 18,
          color: widget.model.hasShutter ? Colors.orange.shade700 : null,
        ),
        label: Text(
          Localization.translate('ستار', lang),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: widget.model.hasShutter ? Colors.orange.shade700 : null,
          ),
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
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final hasSelection = widget.model.selectedZone != null;
    final isMullionSelected =
        widget.model.selection.type == SelectionType.mullion;
    final isInnerDivisionSelected =
        widget.model.selection.type == SelectionType.innerDivision;
    final isFrameSelected =
        widget.model.selection.type == SelectionType.frame &&
        widget.model.getFrameRects().length > 1;

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
        body: Stack(
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
                            widget.model.localizedShutterWidthWarning(lang) ??
                                widget.model.shutterWidthWarning!,
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.model.recommendedShutterBlade != null) ...[
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
                                  : (lang == AppLanguage.english
                                      ? 'Apply recommended blade'
                                      : 'تطبيق الشفرة المقترحة'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () async {
                              widget.model.applyRecommendedShutterBlade();
                              await widget.model.updateShutterDefaultsIfNeeded();
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                if (isInnerDivisionSelected)
                  _buildInnerDivisionToolbar(context)
                else if (isFrameSelected)
                  _buildFrameToolbar(context)
                else ...[
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
                            onTapUp: (details) async {
                              final modelPos = _getModelPos(
                                details.localPosition,
                              );

                              // --- Individual frame dimension tap (coupled windows) ---
                              // First check the number painted directly in
                              // a frame profile.  This is intentionally
                              // narrower than the surrounding profile.
                              InnerDimensionHit? individualTap =
                                  _frameProfileDimensionHit(modelPos);
                              final physicalFrames =
                                  widget.model.getPhysicalFrameInfos();
                              if (physicalFrames.length > 1) {
                                final sorted = List<PhysicalFrameInfo>.from(
                                  physicalFrames,
                                )..sort(
                                    (a, b) => a.rect.left != b.rect.left
                                        ? a.rect.left.compareTo(b.rect.left)
                                        : a.rect.top.compareTo(b.rect.top),
                                  );
                                final hasVaryingHeights = sorted.any(
                                  (f) =>
                                      (f.rect.height -
                                              sorted.first.rect.height)
                                          .abs() >
                                      1.0,
                                );

                                final double scW =
                                    widget.model.sideCoverWidth;
                                double offsetDistTop = 105.0;
                                if (widget.model.hasShutter) {
                                  offsetDistTop += 20.0;
                                }
                                if (widget.model.hasSideCovers &&
                                    !widget.model.removedShutterSides.contains(
                                      'top',
                                    )) {
                                  offsetDistTop += scW + 15.0;
                                }
                                double offsetDistRight = 50.0;
                                if (widget.model.hasSideCovers &&
                                    !widget.model.removedShutterSides.contains(
                                      'right',
                                    )) {
                                  offsetDistRight += scW + 15.0;
                                }
                                double offsetDistLeft = 50.0;
                                if (widget.model.hasSideCovers &&
                                    !widget.model.removedShutterSides.contains(
                                      'left',
                                    )) {
                                  offsetDistLeft += scW + 15.0;
                                }
                                double offsetDistBottom = 50.0;
                                if (widget.model.hasSideCovers &&
                                    widget.model.hasBottomFrame &&
                                    !widget.model.removedShutterSides.contains(
                                      'bottom',
                                    )) {
                                  offsetDistBottom += scW + 15.0;
                                }
                                final bool isSlantedOrArched =
                                    widget.model.archHeight > 0 ||
                                    widget.model.topSlantLeftY != 0 ||
                                    widget.model.topSlantRightY != 0 ||
                                    widget.model.bottomSlantLeftY != 0 ||
                                    widget.model.bottomSlantRightY != 0;

                                // 1. Check individual frame widths (Layer 1)
                                if (individualTap == null) {
                                  double layer1Y;
                                  if (isSlantedOrArched) {
                                    double maxBottomY = math.max(
                                      widget.model.bottomSlantLeftY,
                                      widget.model.bottomSlantRightY,
                                    );
                                    layer1Y =
                                        widget.model.height +
                                        maxBottomY +
                                        offsetDistBottom;
                                  } else {
                                    double wY = -offsetDistTop;
                                    if (widget.model.hasShutter &&
                                        widget.model.isCaissonTunnel) {
                                      wY -= widget.model.shutterBoxHeight;
                                    }
                                    layer1Y = wY + 45.0;
                                  }
                                  for (final f in sorted) {
                                    final xCenter =
                                        (f.rect.left + f.rect.right) / 2;
                                    if ((modelPos.dx - xCenter).abs() <
                                            (f.rect.width / 2).clamp(
                                              30.0,
                                              90.0,
                                            ) &&
                                        (modelPos.dy - layer1Y).abs() < 28.0) {
                                      individualTap = InnerDimensionHit(
                                        f.primaryZoneId,
                                        true,
                                      );
                                      break;
                                    }
                                  }
                                }

                                // 2. Check leftmost frame height
                                if (individualTap == null) {
                                  final leftmost = sorted.first;
                                  final leftYCenter =
                                      (leftmost.rect.top +
                                          leftmost.rect.bottom) /
                                      2;
                                  final leftDimX = -offsetDistLeft;
                                  if ((modelPos.dx - leftDimX).abs() < 28.0 &&
                                      (modelPos.dy - leftYCenter).abs() <
                                          (leftmost.rect.height / 2).clamp(
                                            30.0,
                                            90.0,
                                          )) {
                                    individualTap = InnerDimensionHit(
                                      leftmost.primaryZoneId,
                                      false,
                                    );
                                  }
                                }

                                // 3. Check rightmost frame height
                                if (individualTap == null &&
                                    sorted.length >= 2) {
                                  final rightmost = sorted.last;
                                  final rightYCenter =
                                      (rightmost.rect.top +
                                          rightmost.rect.bottom) /
                                      2;
                                  final rightDimX =
                                      widget.model.width + offsetDistRight;
                                  if ((modelPos.dx - rightDimX).abs() < 28.0 &&
                                      (modelPos.dy - rightYCenter).abs() <
                                          (rightmost.rect.height / 2).clamp(
                                            30.0,
                                            90.0,
                                          )) {
                                    individualTap = InnerDimensionHit(
                                      rightmost.primaryZoneId,
                                      false,
                                    );
                                  }
                                }

                                // 4. Check intermediate frame heights
                                if (individualTap == null &&
                                    sorted.length >= 3 &&
                                    hasVaryingHeights) {
                                  for (
                                    int i = 1;
                                    i < sorted.length - 1;
                                    i++
                                  ) {
                                    final f = sorted[i];
                                    final dimX =
                                        f.rect.left +
                                        math.min(f.rect.width * 0.28, 65.0);
                                    final yCenter =
                                        (f.rect.top + f.rect.bottom) / 2;
                                    if ((modelPos.dx - dimX).abs() < 28.0 &&
                                        (modelPos.dy - yCenter).abs() <
                                            (f.rect.height / 2).clamp(
                                              30.0,
                                              90.0,
                                            )) {
                                      individualTap = InnerDimensionHit(
                                        f.primaryZoneId,
                                        false,
                                      );
                                      break;
                                    }
                                  }
                                }
                              }
                              if (individualTap != null) {
                                _showFrameResizeDialog(context, individualTap);
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
                                    if (zone.boundary.contains(modelPos)) {
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
                                    if (isDouble || isSingle || isSliding) {
                                      if (isSliding) {
                                        final count =
                                            tappedZ.slidingSashesCount;
                                        double chicaneT = 45.0;
                                        final series =
                                            widget.model.activeSlidingSeries ??
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
                                                  i * (sashWidth - chicaneT);
                                              Rect sashRect = Rect.fromLTRB(
                                                left,
                                                tappedZ.boundary.top,
                                                left + sashWidth,
                                                tappedZ.boundary.bottom,
                                              );
                                              if (sashRect.contains(modelPos)) {
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
                                            widget.model.getSectionThickness(
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
                                              ((clampedX - glassR.left) / cellW)
                                                  .clamp(0, currentInnerV)
                                                  .toInt();
                                          int row =
                                              ((clampedY - glassR.top) / cellH)
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
                                          widget.model.getSectionThickness(
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
                                            glassR.width / (currentInnerV + 1);
                                        double cellH =
                                            glassR.height / (currentInnerH + 1);
                                        int col =
                                            ((modelPos.dx - glassR.left) /
                                                    cellW)
                                                .clamp(0, currentInnerV)
                                                .toInt();
                                        int row =
                                            ((modelPos.dy - glassR.top) / cellH)
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
                                            glassR.width / (currentInnerV + 1);
                                        double cellH =
                                            glassR.height / (currentInnerH + 1);
                                        int col =
                                            ((modelPos.dx - glassR.left) /
                                                    cellW)
                                                .clamp(0, currentInnerV)
                                                .toInt();
                                        int row =
                                            ((modelPos.dy - glassR.top) / cellH)
                                                .clamp(0, currentInnerH)
                                                .toInt();
                                        tappedCellId = 'main_cell_${row}_$col';
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

                              final outerTap = widget.model
                                  .checkOuterDimensionTap(modelPos);
                              // The compact number inside each outer frame
                              // has priority over the general dimension
                              // areas, so only the visible number opens its
                              // own edit dialog.
                              final innerTap =
                                  _frameProfileDimensionHit(modelPos) ??
                                  widget.model.checkInnerDimensionTap(modelPos);
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
                                    (details.localPosition - _lastTapPosition!)
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
                                if (_isBottomPanelExpanded ||
                                    _isShutterSelected) {
                                  setState(() {
                                    _isBottomPanelExpanded = false;
                                    _isShutterSelected = false;
                                  });
                                  widget.model.clearSelection();
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
                              if (frameAtBorder != null) {
                                setState(() {
                                  _isShutterSelected = false;
                                  _isBottomPanelExpanded = true;
                                });
                                widget.model.selectFrameByIndex(frameAtBorder);
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

                              if (!widget.model.isShutterOnly &&
                                  isDoubleTap &&
                                  tappedZone) {
                                setState(() {
                                  widget.model.clearSelection();
                                  _isLeftDrawerOpen = true;
                                });
                              }
                            },
                            onSecondaryTapDown: (details) async {
                              await _showDesktopContextMenu(
                                context,
                                details.globalPosition,
                                details.localPosition,
                              );
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
                              if (tappedZ != null &&
                                  (tappedZ.content == ZoneContent.singleSash ||
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
                                if (specToApply != null && tappedZ != null) {
                                  unawaited(
                                    widget.model
                                        .applyGlassSpecificationToAllZones(
                                          specToApply,
                                        ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
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
                                widget.model.deleteSelectedInnerDivision();
                                return;
                              }
                              if (widget.model.selection.type ==
                                  SelectionType.frame) {
                                if (widget.model.getFrameRects().length > 1) {
                                  widget.model.deleteSelectedFrame();
                                  return;
                                }
                                if (widget.model.canBeArchedOrSlanted) {
                                  widget.model.selection = SelectionInfo(
                                    type: SelectionType.frame,
                                  );
                                  widget.model.showZoneMenu = false;
                                  widget.model.activeSubZone = null;
                                  widget.model.refreshUI();
                                  ScaffoldMessenger.of(
                                    context,
                                  ).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
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
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: Colors.amber.shade900,
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
                              if (zone != null &&
                                  cellKey != null &&
                                  cellKey.contains('_cell_')) {
                                final hasSash =
                                    zone.cellIsSash[cellKey] == true ||
                                    zone.cellIsDoubleSash[cellKey] == true;
                                if (hasSash) {
                                  final selected =
                                      await showDialog<Map<String, dynamic>>(
                                        context: context,
                                        builder: (context) =>
                                            ProfileSelectorDialog(
                                              profileType: 'sash',
                                              seriesId:
                                                  activeSeriesForSystem?.id,
                                              hasSimpleGlassForReducer: widget
                                                  .model
                                                  .hasSimpleGlassForReducer,
                                              hasDoubleGlassForRules: widget
                                                  .model
                                                  .hasDoubleGlassForRules,
                                            ),
                                      );
                                  if (!mounted || selected == null) return;
                                  final mutableSelected =
                                      Map<String, dynamic>.from(selected);
                                  mutableSelected['calculated_price'] =
                                      await _sectionPriceForSelectedColor(
                                        mutableSelected,
                                      );
                                  if (!mounted) return;

                                  setState(() {
                                    final newOverrides =
                                        Map<String, Map<String, dynamic>>.from(
                                          zone.cellSashOverrides,
                                        );
                                    newOverrides[cellKey] = mutableSelected;
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
                                final zone = widget.model.selectedZone!;
                                final bounds = zone.boundary;
                                final modelPos =
                                    _getModelPos(details.localPosition);
                                double newRatio =
                                    (modelPos.dx - bounds.left) / bounds.width;
                                newRatio = newRatio.clamp(0.15, 0.85);
                                widget.model.updateZoneDoubleSashRatio(
                                  zone.id,
                                  newRatio,
                                );
                              }
                            },
                            onLongPressEnd: (details) {
                              if (widget.model.selectedZone?.content ==
                                      ZoneContent.doubleSash &&
                                  widget.model.activeSubZone == 'all') {
                                widget.model.saveSnapshotOutside();
                              }
                              _isDraggingHandle = false;
                              _isDraggingHinge = false;
                              _suppressHandleDragForLongPress = false;
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
                                final frameResizeHandle = _frameResizeHandleAt(
                                  touchScreen,
                                );
                                final canSlantOrArch =
                                    isFrameSelected &&
                                    widget.model.canBeArchedOrSlanted &&
                                    (widget.model.selection.zoneId == null ||
                                        widget.model.selection.zoneId ==
                                            'frame:0' ||
                                        widget.model.getFrameRects().length <=
                                            1);
                                if (frameResizeHandle != null) {
                                  _draggedFrameResizeHandle = frameResizeHandle;
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
                                } else if (widget.model.selectedZone != null &&
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
                                  final canInteractWithHardware =
                                      widget.model.isInternalView ||
                                      widget.model.showInternalHardware;
                                  final bool isDoubleBothSelected =
                                      zone.content == ZoneContent.doubleSash &&
                                      widget.model.activeSubZone == 'all';

                                  if (canInteractWithHardware &&
                                      (zone.content == ZoneContent.singleSash ||
                                          zone.content ==
                                              ZoneContent.doubleSash)) {
                                    final activeIsRight = widget.model.activeSubZone != null &&
                                            widget.model.activeSubZone != 'all'
                                        ? widget.model.activeSubZone!.startsWith('right')
                                        : (zone.openDirection != OpenDirection.left);

                                    final sep = 4.0;
                                    final midX =
                                        bounds.left +
                                        bounds.width * zone.doubleSashRatio;
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
                                        (zone.content == ZoneContent.doubleSash)
                                        ? (activeIsRight ? rightR : leftR)
                                        : bounds;

                                    final handleSide =
                                        (zone.content == ZoneContent.doubleSash)
                                        ? (activeIsRight
                                              ? OpenDirection.left
                                              : OpenDirection.right)
                                        : zone.openDirection!;

                                    // Precise hit testing for handle - disabled when both sashes are selected!
                                    if (!isDoubleBothSelected) {
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

                                    final hingeCount =
                                        standardHingeCountForSash(
                                          sashHeight: sashRect.height,
                                          glassStructure: zone.glass.structure,
                                        );

                                    if (hingeCount >= 3 && !hitHandle) {
                                      double hgX = 0;
                                      double hgY = 0;
                                      final hingeRevealOffset =
                                          (widget.model.profileThickness * 0.28)
                                              .clamp(9.0, 18.0)
                                              .toDouble();
                                      if (hingesOnLeft || hingesOnRight) {
                                        hgX = hingesOnRight
                                            ? sashRect.right + hingeRevealOffset
                                            : sashRect.left - hingeRevealOffset;
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
                                            : sashRect.top - hingeRevealOffset;
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
                                  } else if (canInteractWithHardware &&
                                      zone.content == ZoneContent.slidingSash) {
                                    int count = zone.slidingSashesCount;
                                    if (count < 2) count = 2;
                                    double frameT =
                                        zone.sashThickness ??
                                        widget.model.getSectionThickness(
                                          'sash',
                                          fallback: 45.0,
                                        );
                                    double sashWidth =
                                        (bounds.width + (count - 1) * frameT) /
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
                                        (count - 1) * (sashWidth - frameT);
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
                                        ((sashRectLeft.bottom - topYLeft) *
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
                                        ((sashRectRight.bottom - topYRight) *
                                            (1.0 - hRatio));

                                    final handleScreenPosLeft = modelToScreen(
                                      Offset(hXLeft, hYLeft),
                                    );
                                    final handleScreenPosRight = modelToScreen(
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
                                        bounds.width * zone.doubleSashRatio;
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
                                        (touchScreen.dx - dividerScreenX).abs();

                                    final double hitThreshold =
                                        (zone.content == ZoneContent.doubleSash &&
                                                widget.model.activeSubZone == 'all')
                                            ? 60.0
                                            : 30.0;
                                    if (zone.content ==
                                            ZoneContent.doubleSash &&
                                        dist < hitThreshold &&
                                        touchScreen.dy >= topScreenY - 20.0 &&
                                        touchScreen.dy <= bottomScreenY + 20.0) {
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
                                              .getSafeGlassRect(rightR, sashT);
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
                                              .getSafeGlassRect(bounds, sashT);
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
                                      widget.model.pendingDrawStart = modelPos;
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
                                  final screenPending = _modelToScreen(pending);
                                  if ((details.localFocalPoint - screenPending)
                                          .distance >=
                                      5.0) {
                                    widget.model.startDrawing(pending);
                                  }
                                }
                                if (widget.model.drawingStart != null) {
                                  widget.model.updateDrawing(modelPos);
                                } else if (_draggedFrameResizeHandle != null &&
                                    _draggedFrameZoneId != null) {
                                  final handle = _draggedFrameResizeHandle!;
                                  final deltaX =
                                      details.focalPointDelta.dx /
                                      (_userScale * widget.model.canvasScale);
                                  final deltaY =
                                      details.focalPointDelta.dy /
                                      (_userScale * widget.model.canvasScale);
                                  widget.model.resizeFrameFromHandles(
                                    _draggedFrameZoneId!,
                                    moveLeft:
                                        handle == _FrameResizeHandle.left ||
                                        handle == _FrameResizeHandle.topLeft ||
                                        handle == _FrameResizeHandle.bottomLeft,
                                    moveRight:
                                        handle == _FrameResizeHandle.right ||
                                        handle == _FrameResizeHandle.topRight ||
                                        handle ==
                                            _FrameResizeHandle.bottomRight,
                                    moveTop:
                                        handle == _FrameResizeHandle.top ||
                                        handle == _FrameResizeHandle.topLeft ||
                                        handle == _FrameResizeHandle.topRight,
                                    moveBottom:
                                        handle == _FrameResizeHandle.bottom ||
                                        handle ==
                                            _FrameResizeHandle.bottomLeft ||
                                        handle ==
                                            _FrameResizeHandle.bottomRight,
                                    deltaX: deltaX,
                                    deltaY: deltaY,
                                    saveHistory: !_frameResizeHistorySaved,
                                  );
                                  _frameResizeHistorySaved = true;
                                } else if (_isDraggingSlantLeft) {
                                  double dy =
                                      details.focalPointDelta.dy /
                                      (_userScale * widget.model.canvasScale);
                                  widget.model.updateTopSlantAndArch(
                                    leftSlant: (widget.model.topSlantLeftY + dy)
                                        .clamp(-500.0, 500.0),
                                  );
                                } else if (_isDraggingSlantRight) {
                                  double dy =
                                      details.focalPointDelta.dy /
                                      (_userScale * widget.model.canvasScale);
                                  widget.model.updateTopSlantAndArch(
                                    rightSlant:
                                        (widget.model.topSlantRightY + dy)
                                            .clamp(-500.0, 500.0),
                                  );
                                } else if (_isDraggingArch) {
                                  double dy =
                                      details.focalPointDelta.dy /
                                      (_userScale * widget.model.canvasScale);
                                  widget.model.updateTopSlantAndArch(
                                    arch: (widget.model.archHeight - dy / 2)
                                        .clamp(0.0, 800.0),
                                  );
                                } else if (widget.model.selection.type ==
                                    SelectionType.mullion) {
                                  widget.model.moveSelectedMullion(
                                    (widget.model.selection.isHorizontalMullion!
                                            ? details.focalPointDelta.dy
                                            : details.focalPointDelta.dx) /
                                        (_userScale * widget.model.canvasScale),
                                  );
                                } else if (widget.model.selection.type ==
                                    SelectionType.innerDivision) {
                                  double deltaX =
                                      details.focalPointDelta.dx /
                                      (_userScale * widget.model.canvasScale);
                                  double deltaY =
                                      details.focalPointDelta.dy /
                                      (_userScale * widget.model.canvasScale);
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
                                  if (zone.content == ZoneContent.doubleSash) {
                                    final sep = 4.0;
                                    final midX =
                                        parentR.left +
                                        parentR.width * zone.doubleSashRatio;
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
                                  final glassR = widget.model.getSafeGlassRect(
                                    sashR,
                                    sashT,
                                  );

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
                                  if (zone.content == ZoneContent.doubleSash) {
                                    final sep = 4.0;
                                    final midX =
                                        parentR.left +
                                        parentR.width * zone.doubleSashRatio;
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

                                  if (_draggedSashIsHorizontal) {
                                    double newRatio =
                                        (modelPos.dy - glassR.top) /
                                        glassR.height;
                                    widget.model.updateZoneInnerHDivisionRatio(
                                      _draggedSashZoneId!,
                                      isRight,
                                      _draggedSashIndex,
                                      newRatio,
                                    );
                                  } else {
                                    double newRatio =
                                        (modelPos.dx - glassR.left) /
                                        glassR.width;
                                    widget.model.updateZoneInnerVDivisionRatio(
                                      _draggedSashZoneId!,
                                      isRight,
                                      _draggedSashIndex,
                                      newRatio,
                                    );
                                  }
                                } else if (!_suppressHandleDragForLongPress &&
                                    _isDraggingHinge &&
                                    widget.model.selectedZone != null &&
                                    widget.model.isDrawingMode) {
                                  _handleHingeDrag(
                                    details.focalPointDelta,
                                    widget.model.selectedZone!,
                                  );
                                } else if (!_suppressHandleDragForLongPress &&
                                    _isDraggingHandle &&
                                    widget.model.selectedZone != null &&
                                    !(widget.model.selectedZone!.content ==
                                            ZoneContent.doubleSash &&
                                        widget.model.activeSubZone ==
                                            'all') &&
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
                                        Theme.of(context).brightness ==
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
                                      color: Theme.of(
                                        context,
                                      ).cardColor.withValues(alpha: 0.94),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).dividerColor.withValues(alpha: 0.7),
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
                                            onPressed: () => _changeDrawingZoom(
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
                                          color: Theme.of(context).dividerColor,
                                        ),
                                        Semantics(
                                          button: true,
                                          label: 'تصغير الرسم',
                                          child: IconButton(
                                            icon: const Icon(Icons.remove),
                                            onPressed: () => _changeDrawingZoom(
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
                                          color: Theme.of(context).dividerColor,
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
                        ],
                      );
                    },
                  ),
                ),
                _buildInteractiveBottomPanel(context),
              ],
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
                        color: Theme.of(context).brightness == Brightness.dark
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
                      onTap: () {
                        if (!_isLeftDrawerOpen) widget.model.clearSelection();
                        setState(() => _isLeftDrawerOpen = !_isLeftDrawerOpen);
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
                          color: Theme.of(context).brightness == Brightness.dark
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
                          color: Theme.of(context).brightness == Brightness.dark
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
                    onTap: () => setState(() => _isDrawerOpen = !_isDrawerOpen),
                    onVerticalDragUpdate: (details) {
                      setState(() {
                        _rightDrawerHandleTop += details.delta.dy;
                        if (_rightDrawerHandleTop < 0) {
                          _rightDrawerHandleTop = 0;
                        }
                        double maxTop =
                            MediaQuery.of(context).size.height - 120 - 70 - 15;
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
                        color: Theme.of(context).brightness == Brightness.dark
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
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue.shade800,
                        size: 26,
                      ),
                    ),
                  ),
                  Container(
                    width: 330,
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
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

  Widget _buildLeftDrawerContent(BuildContext context) {
    return ScrollConfiguration(
      behavior: _drawerScrollBehavior(context, scrollbars: false),
      child: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final lang = Provider.of<AppSettingsProvider>(context).language;
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

          // When a zone (or a cell inside it) is selected, its own glass is
          // the source of truth for this drawer.  Falling back to the whole
          // drawing is only appropriate before the user selects a target.
          // Otherwise changing a selected pane to a panneau would rebuild the
          // drawer from the neutral value and hide the panneau options.
          final GlassSpecification spec =
              zone?.getGlassForCell(widget.model.activeSubZone) ??
              _tempGlassSpec;
          final structure = spec.structure;
          final slidingJointSpecs = widget.model.zones
              .where((z) => z.content == ZoneContent.slidingSash)
              .expand((z) => [z.glass, ...z.cellGlassSpec.values])
              .toList();

          GlassSpecification fitDoubleGlassToParclose(
            GlassSpecification candidate,
          ) {
            return candidate; // Model resolves joints before touching the spacer.
          }

          Widget? buildParcloseThicknessInfo() {
            if (widget.model.glazingFitMessage != null) {
              return Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  widget.model.glazingFitMessage!,
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }
            if (zone?.content == ZoneContent.slidingSash ||
                (zone == null && widget.model.usesSlidingPrimaryProfiles)) {
              return _slidingGlassFitInfo(spec);
            }
            final usesParclose = widget.model.hasGlazingBeadForContext(
              sliding: false,
            );
            final maximum = widget.model.glazingCapacityForStructure(
              spec.structure,
              sliding: false,
            );
            if (maximum == null || spec.structure == GlassStructure.closed) {
              return null;
            }

            final glassTotal = spec.totalThickness(widget.model.allGlassCache);
            final jointVitrage = widget.model.isPVC
                ? 0.0
                : widget.model.selectedVitrageJointThickness(fallback: 3.0);
            final totalPack = glassTotal + jointVitrage;
            final remainingGap = maximum - totalPack;

            final isExact = remainingGap.abs() < 0.01;
            final isAbove = totalPack > maximum;
            final color =
                isExact || (remainingGap >= 2.0 && remainingGap <= 6.0)
                ? Colors.green.shade700
                : (isAbove ? Colors.red.shade700 : Colors.orange.shade800);
            final icon = isExact || (remainingGap >= 2.0 && remainingGap <= 6.0)
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded;

            String message;
            final hasOpeningSystem = widget.model.zones.any(
              (candidate) =>
                  candidate.content == ZoneContent.singleSash ||
                  candidate.content == ZoneContent.doubleSash,
            );
            final hasSlidingSystem = widget.model.zones.any(
              (candidate) => candidate.content == ZoneContent.slidingSash,
            );
            final openingPrefix = hasOpeningSystem && hasSlidingSystem
                ? 'نظام الفتح (${widget.model.activeSeries?.name ?? ''}): '
                : '';
            final capacityLabel = usesParclose ? 'سعة البيركلوز' : 'سعة الضلفة';
            if (widget.model.isPVC || jointVitrage <= 0) {
              message =
                  openingPrefix +
                  (isExact
                      ? '${Localization.translate('سُمك الزجاج مطابق لسعة البيركلوز', lang).replaceAll('البيركلوز', usesParclose ? 'البيركلوز' : 'الضلفة')}: ${glassTotal.toStringAsFixed(0)} مم'
                      : isAbove
                      ? 'تنبيه: سُمك الزجاج ${glassTotal.toStringAsFixed(0)} مم أكبر من $capacityLabel ${maximum.toStringAsFixed(0)} مم'
                      : 'تنبيه: سُمك الزجاج ${glassTotal.toStringAsFixed(0)} مم أصغر من $capacityLabel ${maximum.toStringAsFixed(0)} مم');
            } else {
              final glassStr = glassTotal.toStringAsFixed(0);
              final jointStr = jointVitrage.toStringAsFixed(0);
              final packStr = totalPack.toStringAsFixed(0);
              final maxStr = maximum.toStringAsFixed(0);
              final gapStr = remainingGap.abs().toStringAsFixed(0);

              if (isAbove) {
                message =
                    openingPrefix +
                    'تنبيه: سُمك الزجاج ($glassStr مم) + جوان الزجاج ($jointStr مم) = $packStr مم يتجاوز $capacityLabel ($maxStr مم) بـ $gapStr مم.';
              } else if (remainingGap < 2.0) {
                message =
                    openingPrefix +
                    'سُمك الزجاج ($glassStr مم) + جوان الزجاج ($jointStr مم) = $packStr مم ($capacityLabel: $maxStr مم). الفراغ المتبقي لـ Joint Bourrage ضيق جداً ($gapStr مم).';
              } else {
                message =
                    openingPrefix +
                    'سُمك الزجاج ($glassStr مم) + جوان الزجاج ($jointStr مم) = $packStr مم | $capacityLabel: $maxStr مم. إذاً الجوان المختار (Joint Bourrage) يجب أن يكون سُمكه $gapStr مم.';
              }
            }

            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          Widget? buildSlidingParcloseThicknessInfo() {
            final hasOpeningSystem = widget.model.zones.any(
              (candidate) =>
                  candidate.content == ZoneContent.singleSash ||
                  candidate.content == ZoneContent.doubleSash,
            );
            final hasSlidingSystem = widget.model.zones.any(
              (candidate) => candidate.content == ZoneContent.slidingSash,
            );
            if (!hasOpeningSystem ||
                !hasSlidingSystem ||
                spec.structure == GlassStructure.closed) {
              return null;
            }

            final usesParclose = widget.model.hasGlazingBeadForContext(
              sliding: true,
            );
            final maximum = widget.model.glazingCapacityForStructure(
              spec.structure,
              sliding: true,
            );
            if (maximum == null) return null;

            final glassTotal = spec.totalThickness(widget.model.allGlassCache);
            final sides = spec.jointTwoSides ? 2 : 1;
            final requiredPerSide = (maximum - glassTotal) / sides;
            final isAbove = requiredPerSide < 0;
            final color = isAbove ? Colors.red.shade700 : Colors.blue.shade700;
            final icon = isAbove
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded;
            final glassStr = glassTotal.toStringAsFixed(0);
            final maxStr = maximum.toStringAsFixed(0);
            final jointStr = requiredPerSide.abs().toStringAsFixed(1);
            final sideText = sides == 2 ? 'من جهتين' : 'من جهة واحدة';
            final seriesName = widget.model.activeSlidingSeries?.name ?? '';
            final capacityLabel = usesParclose ? 'سعة البيركلوز' : 'سعة الضلفة';
            final message = isAbove
                ? 'نظام المنزلق ($seriesName): سُمك الزجاج $glassStr مم يتجاوز $capacityLabel $maxStr مم بـ $jointStr مم.'
                : 'نظام المنزلق ($seriesName): سُمك الزجاج $glassStr مم، الجوان المطلوب $jointStr مم $sideText، و$capacityLabel $maxStr مم.';

            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final parcloseThicknessInfo = buildParcloseThicknessInfo();
          final slidingParcloseThicknessInfo =
              buildSlidingParcloseThicknessInfo();
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
                  thicknessOuter:
                      spec.thicknessOuter ?? kDefaultGlassPaneThickness,
                  thicknessInner:
                      spec.thicknessInner ?? kDefaultGlassPaneThickness,
                  jointTwoSides: spec.jointTwoSides,
                )
              : null;

          Widget buildProcessingChip(
            String label,
            GlassProcessing type,
            bool isOuter,
            void Function(GlassProcessing) onTap,
          ) {
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
                Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    Localization.translate('نوع المعالجة:', lang),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    buildProcessingChip(
                      Localization.translate('Simple', lang),
                      GlassProcessing.none,
                      isOuter,
                      (t) => updateProcessing(t),
                    ),
                    buildProcessingChip(
                      Localization.translate('Feuillette', lang),
                      GlassProcessing.laminated,
                      isOuter,
                      (t) => updateProcessing(t),
                    ),
                    buildProcessingChip(
                      Localization.translate('Low-e', lang),
                      GlassProcessing.lowE,
                      isOuter,
                      (t) => updateProcessing(t),
                    ),
                    FilterChip(
                      label: Text(
                        Localization.translate('Trempé', lang),
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
                Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    Localization.translate('المظهر:', lang),
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
                            (f) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _ContentButton(
                                label: _getFinishName(f),
                                icon: Icons.blur_on_rounded,
                                selected: finish == f,
                                showWarning:
                                    widget.model.getPriceForFinish(f, color) ==
                                    0.0,
                                onPressed: () {
                                  final GlassColor nextColor =
                                      f == GlassFinish.stopSol
                                      ? (isOuter
                                            ? spec.colorOuter
                                            : spec.colorInner)
                                      : GlassColor.transparent;
                                  double defThick = widget.model
                                      .getThicknessForFinish(f, nextColor);
                                  if (defThick == 0.0) defThick = 5.0;

                                  final newSpec = fitDoubleGlassToParclose(
                                    spec.copyWith(
                                      finishOuter: isOuter ? f : null,
                                      finishInner: !isOuter ? f : null,
                                      colorOuter: isOuter ? nextColor : null,
                                      colorInner: !isOuter ? nextColor : null,
                                      thicknessOuter: isOuter ? defThick : null,
                                      thicknessInner: !isOuter
                                          ? defThick
                                          : null,
                                    ),
                                  );
                                  if (zone != null) {
                                    widget.model.updateSelectedZoneGlass(
                                      finishOuter: isOuter ? f : null,
                                      finishInner: !isOuter ? f : null,
                                      colorOuter: isOuter ? nextColor : null,
                                      colorInner: !isOuter ? nextColor : null,
                                      thicknessOuter: isOuter ? defThick : null,
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
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      _tr('لون الزجاج (ستوبسول):'),
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
                              (c) => Padding(
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

                                    final newSpec = fitDoubleGlassToParclose(
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
                    final isSliding67Family = widget.model.isSliding67Family;
                    final isSliding =
                        widget.systemMode == 'sliding' ||
                        widget.model.systemMode == 'sliding' ||
                        zone?.content == ZoneContent.slidingSash;
                    if (isSliding && isSliding67Family) {
                      final double minGasket = spec.jointTwoSides ? 4.0 : 2.0;
                      final double maxAllowed =
                          24.0 - minGasket; // 20.0 or 22.0
                      if (spec.structure == GlassStructure.double) {
                        final double tOther = isOuter
                            ? (spec.thicknessInner ??
                                  kDefaultGlassPaneThickness)
                            : (spec.thicknessOuter ??
                                  kDefaultGlassPaneThickness);
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
                      builder: (context, controller) => SingleChildScrollView(
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
                                      thicknessOuter: isOuter ? thickVal : null,
                                      thicknessInner: !isOuter
                                          ? thickVal
                                          : null,
                                    ),
                                  );
                                  if (zone != null) {
                                    widget.model.updateSelectedZoneGlass(
                                      thicknessOuter: isOuter ? thickVal : null,
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
                    Localization.translate('خصائص الزجاج', lang),
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
              if (slidingParcloseThicknessInfo != null)
                slidingParcloseThicknessInfo,
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
                    Expanded(
                      child: Text(
                        _tr('نسبة تقسيم الضلفة (ضلفة أكبر من ضلفة)'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.blue.shade300
                              : Colors.blue.shade800,
                          fontSize: 13,
                        ),
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
                              'اليسرى: ${(targetZone.doubleSashRatio * 100).toInt()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Text(
                              'اليمنى: ${((1.0 - targetZone.doubleSashRatio) * 100).toInt()}%',
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
                              child: Text(
                                _tr('متساويين (50%)'),
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
                                  SnackBar(
                                    content: Text(
                                      _tr('يرجى إدخال قياس صحيح بالمليمتر'),
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
                                      'القياس لا يمكن أن يتجاوز 80% من مجموع عرض الضلفات (${maxVal.toInt()} مم)',
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
                                      'القياس لا يمكن أن يقل عن 15% من مجموع عرض الضلفات (${minVal.toInt()} مم)',
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
                                        labelText: Localization.translate(
                                          'عرض الضلفة اليسرى (مم)',
                                          lang,
                                        ),
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

              Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  Localization.translate('هيكل الزجاج:', lang),
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _HorizontalWheelScrollArea(
                builder: (context, controller) => SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: GlassStructure.values
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _ContentButton(
                              label: _getStructureName(s),
                              icon: Icons.layers_rounded,
                              selected: structure == s,
                              onPressed: () async {
                                String? defaultSubtype;
                                String? defaultColor;
                                if (s == GlassStructure.closed) {
                                  final panneaux = widget.model.allGlassCache
                                      .where(
                                        (g) =>
                                            g['type']
                                                .toString()
                                                .toLowerCase() ==
                                            'panneau',
                                      )
                                      .toList();
                                  final subtypes = panneaux
                                      .map(
                                        (g) => (g['subtype'] ?? '').toString(),
                                      )
                                      .where((s) => s.isNotEmpty)
                                      .toSet()
                                      .toList();
                                  if (subtypes.isNotEmpty) {
                                    final savedSubtype = spec.panneauSubtype;
                                    defaultSubtype =
                                        spec.structure ==
                                                GlassStructure.closed &&
                                            savedSubtype != null &&
                                            subtypes.any(
                                              (value) =>
                                                  value.toLowerCase() ==
                                                  savedSubtype.toLowerCase(),
                                            )
                                        ? savedSubtype
                                        : subtypes.firstWhere(
                                            (value) =>
                                                !isDecorPanelSubtype(value),
                                            orElse: () => subtypes.first,
                                          );
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
                                            (g) => (g['color'] ?? '')
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
                                final GlassColor? structureColorOuter =
                                    s != GlassStructure.closed &&
                                        spec.finishOuter != GlassFinish.stopSol
                                    ? GlassColor.transparent
                                    : null;
                                final GlassColor? structureColorInner =
                                    s != GlassStructure.closed &&
                                        spec.finishInner != GlassFinish.stopSol
                                    ? GlassColor.transparent
                                    : null;
                                if (s == GlassStructure.double) {
                                  defaultThickOuter =
                                      spec.thicknessOuter ??
                                      widget.model.getThicknessForFinish(
                                        spec.finishOuter,
                                        structureColorOuter ?? spec.colorOuter,
                                      );
                                  defaultThickInner =
                                      spec.thicknessInner ??
                                      widget.model.getThicknessForFinish(
                                        spec.finishInner,
                                        structureColorInner ?? spec.colorInner,
                                      );
                                  if (defaultThickOuter == 0.0) {
                                    defaultThickOuter = 5.0;
                                  }
                                  if (defaultThickInner == 0.0) {
                                    defaultThickInner = 5.0;
                                  }
                                } else if (s == GlassStructure.simple) {
                                  defaultThickOuter =
                                      spec.thicknessOuter ??
                                      widget.model.getThicknessForFinish(
                                        spec.finishOuter,
                                        structureColorOuter ?? spec.colorOuter,
                                      );
                                  if (defaultThickOuter == 0.0) {
                                    defaultThickOuter = 5.0;
                                  }
                                }

                                final newSpec = fitDoubleGlassToParclose(
                                  spec.copyWith(
                                    structure: s,
                                    hasGas:
                                        s == GlassStructure.double &&
                                            spec.structure !=
                                                GlassStructure.double
                                        ? true
                                        : null,
                                    panneauSubtype: defaultSubtype,
                                    panneauColor: defaultColor,
                                    colorOuter: structureColorOuter,
                                    colorInner: structureColorInner,
                                    thicknessOuter: defaultThickOuter,
                                    thicknessInner: defaultThickInner,
                                  ),
                                );
                                if (zone != null) {
                                  await widget.model.updateSelectedZoneGlass(
                                    structure: s,
                                    hasGas:
                                        s == GlassStructure.double &&
                                            spec.structure !=
                                                GlassStructure.double
                                        ? true
                                        : null,
                                    panneauSubtype: defaultSubtype,
                                    panneauColor: defaultColor,
                                    colorOuter: structureColorOuter,
                                    colorInner: structureColorInner,
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
                Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    Localization.translate('المظهر (بانو):', lang),
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

                    // دائماً نضيف البارداج كخيار ثابت من بروفيلات السلسلة.
                    // تسعيره لاحقاً يكون بعدد قطع المخزون الكاملة.
                    const String bardageKey = 'bardage';
                    if (!subtypes.any(isBardagePanelSubtype)) {
                      subtypes.add(bardageKey);
                    }

                    String getArabicSubtypeName(String sub) {
                      final s = sub.toLowerCase();
                      if (s.contains('resine') ||
                          s.contains('ارزين') ||
                          s.contains('أرزين')) {
                        return 'ارزين';
                      }
                      if (s.contains('plexi')) return 'بليكسي';
                      if (s.contains('decore') || s.contains('ديكور')) {
                        return 'بانو ديكور';
                      }
                      if (s.contains('sandwitch') ||
                          s.contains('sandwich') ||
                          s == 'panneau' ||
                          s == 'بانو') {
                        return 'بانو';
                      }
                      if (s.contains('aluco') || s.contains('الوكو')) {
                        return 'الوكو';
                      }
                      if (isBardagePanelSubtype(s)) {
                        return 'بارداش';
                      }
                      return sub;
                    }

                    IconData getSubtypeIcon(String sub) {
                      final s = sub.toLowerCase();
                      if (isBardagePanelSubtype(s)) {
                        return Icons.view_stream_rounded;
                      }
                      return Icons.blur_on_rounded;
                    }

                    return _HorizontalWheelScrollArea(
                      builder: (context, controller) => SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: subtypes.map((sub) {
                            final isSelected =
                                (spec.panneauSubtype ?? '').toLowerCase() ==
                                sub.toLowerCase();
                            final isBardage = isBardagePanelSubtype(sub);
                            final isDecor = isDecorPanelSubtype(sub);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _ContentButton(
                                label: getArabicSubtypeName(sub),
                                icon: getSubtypeIcon(sub),
                                selected: isSelected,
                                onPressed: () async {
                                  final subRows = panneaux
                                      .where(
                                        (g) =>
                                            (g['subtype'] ?? '')
                                                .toString()
                                                .toLowerCase() ==
                                            sub.toLowerCase(),
                                      )
                                      .toList();
                                  final selectedFrameColor =
                                      (widget.model.selectedDbColor?['name'] ??
                                              widget
                                                  .model
                                                  .selectedDbColor?['color_name'] ??
                                              widget.model.frameColor.name)
                                          .toString()
                                          .trim();
                                  String firstColor = isBardage
                                      ? selectedFrameColor
                                      : 'أبيض';
                                  if (!isBardage && subRows.isNotEmpty) {
                                    final colorsList = subRows
                                        .map(
                                          (g) => (g['color'] ?? '')
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
                                    targetFinish = GlassFinish.paneauSandwitch;
                                  }

                                  final bardageProfile = isBardage
                                      ? widget
                                            .model
                                            .componentOverrides['البارداج (Bardage)']
                                      : null;
                                  final rawBardageThickness =
                                      bardageProfile?['thickness'];
                                  final bardageThickness =
                                      rawBardageThickness is num
                                      ? rawBardageThickness.toDouble()
                                      : double.tryParse(
                                          rawBardageThickness?.toString() ?? '',
                                        );
                                  final rawBardageId = bardageProfile?['id'];
                                  final bardageProfileId = rawBardageId is num
                                      ? rawBardageId.toInt()
                                      : int.tryParse(
                                          rawBardageId?.toString() ?? '',
                                        );
                                  Map<String, dynamic>? decorProduct;
                                  if (isDecor && subRows.isNotEmpty) {
                                    decorProduct = subRows.firstWhere(
                                      (row) =>
                                          row['id']?.toString() ==
                                          spec.panneauProductId?.toString(),
                                      orElse: () => subRows.first,
                                    );
                                    final productColor =
                                        (decorProduct['color'] ?? '')
                                            .toString()
                                            .trim();
                                    if (productColor.isNotEmpty) {
                                      firstColor = productColor;
                                    }
                                  }
                                  final rawDecorId = decorProduct?['id'];
                                  final decorProductId = rawDecorId is num
                                      ? rawDecorId.toInt()
                                      : int.tryParse(
                                          rawDecorId?.toString() ?? '',
                                        );
                                  final decorThickness = decorProduct == null
                                      ? null
                                      : _catalogNumber(
                                          decorProduct,
                                          'thickness',
                                        );
                                  final newSpec = spec.copyWith(
                                    panneauSubtype: sub,
                                    panneauColor: firstColor,
                                    bardageUsesFrameColor: isBardage
                                        ? true
                                        : spec.bardageUsesFrameColor,
                                    structure: GlassStructure.closed,
                                    finishOuter: targetFinish,
                                    finishInner: targetFinish,
                                    panneauProductId: isBardage
                                        ? bardageProfileId
                                        : decorProductId,
                                    thicknessOuter: isBardage
                                        ? bardageThickness
                                        : decorThickness,
                                  );
                                  if (zone != null) {
                                    if (isDecor) {
                                      final placement =
                                          await _prepareDecorPanelPlacement(
                                            zone: zone,
                                            cellId: widget.model.activeSubZone,
                                            spec: newSpec,
                                          );
                                      if (!placement.allowed) return;
                                      widget.model.activeSubZone =
                                          placement.cellId;
                                    }
                                    await widget.model.updateSelectedZoneGlass(
                                      panneauSubtype: sub,
                                      panneauColor: firstColor,
                                      bardageUsesFrameColor: isBardage
                                          ? true
                                          : spec.bardageUsesFrameColor,
                                      finishOuter: targetFinish,
                                      finishInner: targetFinish,
                                      structure: GlassStructure.closed,
                                      panneauProductId: isBardage
                                          ? bardageProfileId
                                          : decorProductId,
                                      thicknessOuter: isBardage
                                          ? bardageThickness
                                          : decorThickness,
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
                if (isDecorPanelSubtype(spec.panneauSubtype)) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      _tr('رسم ومقاس البانو ديكور:'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final uniqueProducts = <String, Map<String, dynamic>>{};
                      for (final product in widget.model.allGlassCache) {
                        if (product['type'].toString().toLowerCase() !=
                                'panneau' ||
                            !isDecorPanelSubtype(
                              product['subtype']?.toString(),
                            )) {
                          continue;
                        }
                        final id = product['id']?.toString();
                        if (id != null && id.isNotEmpty) {
                          uniqueProducts.putIfAbsent(id, () => product);
                        }
                      }
                      final products = uniqueProducts.values.toList();
                      if (products.isEmpty) {
                        return Text(
                          _tr('لا يوجد بانو ديكور في منتجات الزجاج.'),
                          style: TextStyle(color: Colors.red, fontSize: 10),
                        );
                      }
                      final savedId = spec.panneauProductId?.toString();
                      final currentId = uniqueProducts.containsKey(savedId)
                          ? savedId
                          : products.first['id'].toString();

                      return DropdownButtonFormField<String>(
                        value: currentId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: products.map((product) {
                          final width = _catalogNumber(
                            product,
                            'visible_width',
                          );
                          final height = _catalogNumber(product, 'height');
                          final name = (product['name'] ?? 'بانو ديكور')
                              .toString();
                          return DropdownMenuItem<String>(
                            value: product['id'].toString(),
                            child: Text(
                              '$name - ${width.toStringAsFixed(0)} × ${height.toStringAsFixed(0)} مم',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          if (value == null) return;
                          final chosen = uniqueProducts[value]!;
                          final chosenId = int.tryParse(value);
                          final thickness = _catalogNumber(chosen, 'thickness');
                          final colorsForProduct = widget.model.allGlassCache
                              .where(
                                (row) =>
                                    row['id']?.toString() == value &&
                                    (row['color'] ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty,
                              )
                              .map(
                                (row) => (row['color'] ?? '').toString().trim(),
                              )
                              .toList();
                          final selectedColor =
                              colorsForProduct.any(
                                (color) =>
                                    color.toLowerCase() ==
                                    (spec.panneauColor ?? '').toLowerCase(),
                              )
                              ? spec.panneauColor
                              : (colorsForProduct.isEmpty
                                    ? spec.panneauColor
                                    : colorsForProduct.first);
                          final newSpec = spec.copyWith(
                            panneauProductId: chosenId,
                            panneauColor: selectedColor,
                            thicknessOuter: thickness,
                          );
                          if (zone != null) {
                            final placement = await _prepareDecorPanelPlacement(
                              zone: zone,
                              cellId: widget.model.activeSubZone,
                              spec: newSpec,
                            );
                            if (!placement.allowed) return;
                            widget.model.activeSubZone = placement.cellId;
                            await widget.model.updateSelectedZoneGlass(
                              panneauProductId: chosenId,
                              panneauColor: selectedColor,
                              thicknessOuter: thickness,
                            );
                          } else {
                            setState(() => _tempGlassSpec = newSpec);
                          }
                          _startPaintbrushMode(glassSpec: newSpec);
                        },
                      );
                    },
                  ),
                ],
                // ألوان البانو — تُخفى عند اختيار البارداج لأنه بروفيل بلا ألوان
                if (!(spec.panneauSubtype ?? '').toLowerCase().contains(
                  'bardage',
                )) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      _tr('لون البانو:'),
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
                      final activeIsDecor = isDecorPanelSubtype(activeSub);
                      final subRows = panneaux
                          .where(
                            (g) =>
                                (g['subtype'] ?? '').toString().toLowerCase() ==
                                    activeSub.toLowerCase() &&
                                (!activeIsDecor ||
                                    spec.panneauProductId == null ||
                                    g['id']?.toString() ==
                                        spec.panneauProductId.toString()),
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
                        builder: (context, controller) => SingleChildScrollView(
                          controller: controller,
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: allowedColors.map((colorName) {
                                final isSelected =
                                    (spec.panneauColor ?? '').toLowerCase() ==
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
                                        widget.model.updateSelectedZoneGlass(
                                          panneauColor: colorName,
                                        );
                                      } else {
                                        setState(() {
                                          _tempGlassSpec = newSpec;
                                        });
                                      }
                                      _startPaintbrushMode(glassSpec: newSpec);
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
                                                  color: Colors.blue.withValues(
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
                ] else ...[
                  // اختيار مقاس البارداج المتوفر في قاعدة البيانات
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      _tr('مقاس وسماكة البارداج:'),
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
                            return isBardagePanelSubtype(t) ||
                                isBardagePanelSubtype(n);
                          }).toList();

                      final List<Map<String, dynamic>> productsList = [];

                      if (bardageSections.isNotEmpty) {
                        for (var s in bardageSections) {
                          productsList.add({...s.toMap(), 'is_profile': true});
                        }
                      }

                      final savedProductId = spec.panneauProductId;
                      final int? currentProductId =
                          productsList.any((p) => p['id'] == savedProductId)
                          ? savedProductId
                          : (productsList.isNotEmpty
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
                          child: Text(
                            _tr(
                              'أضف بروفيل بارداش إلى هذه السيري وحدد عرضه الظاهر وسمكه وطول بارته ليتم الحساب.',
                            ),
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
                                  (p['thickness'] as num?)?.toDouble() ?? 24.0;
                              final double visibleW = dbVw > 0 ? dbVw : dbThick;
                              final double thickness = dbThick;
                              return DropdownMenuItem<int>(
                                value: p['id'] as int?,
                                child: Text(
                                  '$name - العرض: ${visibleW.toStringAsFixed(0)} مم (السمك: ${thickness.toStringAsFixed(0)} مم)',
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
                                final rawThickness = chosen['thickness'];
                                final profileThickness = rawThickness is num
                                    ? rawThickness.toDouble()
                                    : double.tryParse(
                                            rawThickness?.toString() ?? '',
                                          ) ??
                                          0.0;
                                final newSpec = spec.copyWith(
                                  panneauProductId: val,
                                  thicknessOuter: profileThickness,
                                );

                                if (chosen['is_profile'] == true) {
                                  final mutableChosen =
                                      Map<String, dynamic>.from(chosen);
                                  widget
                                          .model
                                          .componentOverrides['البارداج (Bardage)'] =
                                      mutableChosen;
                                  await widget.model
                                      .refreshBardageColorPrices();
                                } else {
                                  widget.model.componentOverrides.remove(
                                    'البارداج (Bardage)',
                                  );
                                }

                                if (zone != null) {
                                  widget.model.updateSelectedZoneGlass(
                                    panneauProductId: val,
                                    thicknessOuter: profileThickness,
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
                  Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      _tr('لون البارداج:'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final colorList = widget.model.availableColors;
                      final frameColorName =
                          (widget.model.selectedDbColor?['name'] ??
                                  widget.model.selectedDbColor?['color_name'] ??
                                  widget.model.frameColor.name)
                              .toString()
                              .trim();
                      final effectiveColorName = widget.model
                          .getBardageColorNameForSpec(spec);

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
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 10,
                                          ),
                                          child: ChoiceChip(
                                            label: Text(
                                              '${_tr('تلقائي:')} $frameColorName',
                                              style: const TextStyle(
                                                fontSize: 9,
                                              ),
                                            ),
                                            avatar: const Icon(
                                              Icons.sync_rounded,
                                              size: 16,
                                            ),
                                            selected:
                                                spec.bardageUsesFrameColor,
                                            onSelected: (_) async {
                                              final newSpec = spec.copyWith(
                                                panneauColor: frameColorName,
                                                bardageUsesFrameColor: true,
                                              );
                                              if (zone != null) {
                                                await widget.model
                                                    .updateSelectedZoneGlass(
                                                      panneauColor:
                                                          frameColorName,
                                                      bardageUsesFrameColor:
                                                          true,
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
                                          ),
                                        ),
                                        ...colorList.map((colorMap) {
                                          final colorName =
                                              (colorMap['name'] ??
                                                      colorMap['color_name'] ??
                                                      '')
                                                  .toString();
                                          final isSelected =
                                              !spec.bardageUsesFrameColor &&
                                              effectiveColorName
                                                      .toLowerCase() ==
                                                  colorName.toLowerCase();
                                          final woodImage =
                                              _getWoodTextureImage(colorMap);
                                          final parsedColor =
                                              getEffectiveGradientColors(
                                                FrameColor.white,
                                                colorMap,
                                              )[1];

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 10,
                                            ),
                                            child: GestureDetector(
                                              onTap: () async {
                                                final newSpec = spec.copyWith(
                                                  panneauColor: colorName,
                                                  bardageUsesFrameColor: false,
                                                );
                                                if (zone != null) {
                                                  await widget.model
                                                      .updateSelectedZoneGlass(
                                                        panneauColor: colorName,
                                                        bardageUsesFrameColor:
                                                            false,
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
                                                            : Colors
                                                                  .grey
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
                                                                  0.3,
                                                                ),
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
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: isSelected
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                        color: isSelected
                                                            ? Colors
                                                                  .blue
                                                                  .shade900
                                                            : Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                          ),
                          if (colorList.isEmpty)
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                _tr('لا توجد ألوان مضافة لهذه السلسلة.'),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            _tr('اتجاه شرائح البارداج:'),
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
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.view_stream_rounded,
                                  size: 12,
                                  color: Colors.orange,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  _tr('يُحسب بالمتر الطولي كبروفيل'),
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
              ] else if (structure == GlassStructure.double) ...[
                const Divider(),
                Text(
                  Localization.translate('الوجه الخارجي', lang),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 12,
                  ),
                ),
                buildGlassLayer(true),
                const SizedBox(height: 8),
                const Divider(),
                Text(
                  Localization.translate('الوجه الداخلي', lang),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 12,
                  ),
                ),
                buildGlassLayer(false),
                const SizedBox(height: 12),
                Text(
                  Localization.translate(
                    'سمك الفاصل (Intercall) — المقترح تلقائياً حسب Parclose:',
                    lang,
                  ),
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
                      _tr(
                        'لا توجد Parclose مناسبة لسماكة لوحي الزجاج المختارة. اختر Parclose مزدوجة متوافقة أولاً.',
                      ),
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
                            spec.thicknessOuter ?? kDefaultGlassPaneThickness;
                        final double tInner =
                            spec.thicknessInner ?? kDefaultGlassPaneThickness;
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
                        final newSpec = spec.copyWith(intercallThickness: val);
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
                      Text(
                        _tr('يحتوي على غاز (Gas)'),
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
                    Text(
                      Localization.translate(
                        'ديكور الزجاج المزدوج (ورود):',
                        lang,
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontSize: 12,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Localization.translate('وردات', lang),
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
                    Text(
                      Localization.translate('أفقي:', lang),
                      style: const TextStyle(fontSize: 12),
                    ),
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
                        final newSpec = spec.copyWith(decorH: spec.decorH + 1);
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
                    Text(
                      Localization.translate('عمودي:', lang),
                      style: const TextStyle(fontSize: 12),
                    ),
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
                        final newSpec = spec.copyWith(decorV: spec.decorV + 1);
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
                          (g) => g['type'].toString().toLowerCase().contains(
                            'baguette',
                          ),
                        )
                        .toList();

                    if (baguettes.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _tr(
                            'لا يوجد باجيت ديكور في قاعدة البيانات. يرجى إضافتها أولاً.',
                          ),
                          style: TextStyle(color: Colors.red, fontSize: 11),
                        ),
                      );
                    }

                    // Safe int id extraction
                    int? specBaguetteId = (spec.decorBaguetteId is int)
                        ? spec.decorBaguetteId as int
                        : int.tryParse(spec.decorBaguetteId?.toString() ?? '');

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
                            Text(
                              Localization.translate('نوع الباجيت:', lang),
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  isExpanded: true,
                                  value: safeSelectedId,
                                  items: uniqueBaguettes.map((b) {
                                    final id = (b['id'] as num?)?.toInt() ?? 0;
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
                                      _startPaintbrushMode(glassSpec: newSpec);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              Localization.translate('اللون:', lang),
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
                            (g) => g['type'].toString().toLowerCase().contains(
                              'rosette',
                            ),
                          )
                          .toList();

                      if (rosettes.isEmpty) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            Localization.translate(
                              'لا توجد وردات ديكور في قاعدة البيانات. يرجى إضافتها أولاً.',
                              lang,
                            ),
                            style: TextStyle(color: Colors.red, fontSize: 11),
                          ),
                        );
                      }

                      // Safe int id extraction for rosette
                      int? specRosetteId = (spec.decorRosetteId is int)
                          ? spec.decorRosetteId as int
                          : int.tryParse(spec.decorRosetteId?.toString() ?? '');

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
                        (r) => (r['id'] as num?)?.toInt() == specRosetteId,
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
                              Text(
                                _tr('نوع الوردة:'),
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
                                          style: const TextStyle(fontSize: 12),
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
                                            () => _tempGlassSpec = newSpec,
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
                                    items: [
                                      DropdownMenuItem(
                                        value: 1,
                                        child: Text(
                                          _tr('شكل 1 (نجمة)'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 2,
                                        child: Text(
                                          _tr('شكل 2 (منحني)'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 3,
                                        child: Text(
                                          _tr('شكل 3 (باروكي)'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 4,
                                        child: Text(
                                          _tr('شكل 4 (معين مصمت)'),
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
                                            () => _tempGlassSpec = newSpec,
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
              ] else ...[
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
          final lang = Provider.of<AppSettingsProvider>(context).language;
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
                    unawaited(
                      _syncSlidingMontantOverrideFromFlags(
                        central: key.startsWith('central_'),
                      ),
                    );
                  },
                  activeColor: Colors.blue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            );
          }

          Widget buildCompactSlimOption(
            String label,
            String key,
            WindowZone zone,
          ) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: zone.slidingMontantSlim[key] ?? false,
                  onChanged: (v) {
                    setState(() {
                      zone.slidingMontantSlim[key] = v ?? false;
                      if (zone.slidingMontantSlim[key] == true &&
                          widget.model.selectedSlimMontantProfile == null) {
                        final candidates = widget.model
                            .getSlidingSlimCandidates();
                        if (candidates.isNotEmpty) {
                          widget.model.applySlidingMontantSlimOverride(
                            candidates.first,
                          );
                        }
                      }
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
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.shade900.withValues(alpha: 0.3)
                              : Colors.blue.shade50)
                        : (Theme.of(context).brightness == Brightness.dark
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
                            ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.blue.shade300
                                  : Colors.blue.shade900)
                            : (Theme.of(context).brightness == Brightness.dark
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
                              ? (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.blue.shade300
                                    : Colors.blue.shade900)
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!widget.model.isInternalView)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: const Icon(Icons.handyman_outlined),
                  title: Text(
                    Localization.translate(
                      'إظهار المقابض والمفاصل والتجاويف في الوجه الخارجي',
                      lang,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: widget.model.showInternalHardware,
                  onChanged: widget.model.setInternalHardwareVisibility,
                ),
              const SizedBox(height: 20),

              Text(
                widget.model.selectedDbColor != null
                    ? '${Localization.translate('اللون:', lang)} ${widget.model.selectedDbColor!['name']}'
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
                children:
                    widget.model.colorsLoading &&
                        widget.model.availableColors.isEmpty
                    ? const [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ]
                    : widget.model.availableColors.map((dbColor) {
                        final isSelected =
                            widget.model.selectedDbColor != null &&
                            widget.model.selectedDbColor!['id'] ==
                                dbColor['id'];
                        Color parsedColor = getEffectiveGradientColors(
                          FrameColor.white,
                          dbColor,
                        )[1];
                        final woodImage = _getWoodTextureImage(dbColor);
                        return GestureDetector(
                          onTap: () {
                            widget.model.selectProfileColorWithDefaults(
                              dbColor,
                            );
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
                    ? '${Localization.translate('لون الإكسسوارات:', lang)} ${widget.model.selectedAccessoryColor!['name']}'
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
                  value: widget.model.selectedFrameHasBottom,
                  activeThumbColor: Colors.blue,
                  onChanged: widget.model.canEditSelectedBottomFrame
                      ? (value) => widget.model.toggleBottomFrame(value)
                      : null,
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
                activeThumbColor: Colors.blue,
                onChanged: (value) => widget.model.toggleShowWall(value),
              ),
              if (widget.model.showWall) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _tr('لون الجدار'),
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
                                  Text(
                                    _tr('أحمر'),
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
                  activeThumbColor: Colors.blue,
                  // The user may always explicitly enable or disable the
                  // couvre-joint. Catalogue capability rules control the
                  // default/profile choice, never the switch availability.
                  onChanged: (value) {
                    if (value != null) {
                      widget.model.toggleSideCovers(value);
                    }
                  },
                );
              }()),
              if (widget.model.hasSideCovers) ...[
                if ((widget.model.getSectionByType('frame')?.couvreJointWidth ??
                            0) ==
                        0 &&
                    widget.model.canUseStandaloneSideCover &&
                    widget.model.availableSideCovers.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'اختر الغطاء الجانبي',
                          lang,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
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
                            widget.model.sideCoverOverride = widget
                                .model
                                .selectedSideCover!
                                .toMap();
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
                if (widget.model.integratedFrameSideCoverWidth == 0 &&
                    (widget.model.selectedSideCover?.couvreJointWidth ?? 0) >
                        0 &&
                    ((widget.model.selectedSideCover?.visibleWidth ?? 0) > 0 ||
                        (widget.model.selectedSideCover?.visibleWidth2 ?? 0) >
                            0))
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
                        (() {
                          final cover = widget.model.selectedSideCover!;
                          final secondWidth = cover.visibleWidth > 0
                              ? cover.visibleWidth
                              : cover.visibleWidth2;
                          final width = widget.model.sideCoverUseSecondWidth
                              ? secondWidth
                              : cover.couvreJointWidth;
                          return '${width.toStringAsFixed(0)} mm';
                        })(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ),
              ],
              if (!widget.model.isShutterOnly)
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
                if (widget.model.shutterHeightWarning != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.model.shutterHeightWarning!,
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.model.shutterWidthWarning != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.straighten,
                              color: Colors.orange.shade800,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.model.localizedShutterWidthWarning(lang) ??
                                    widget.model.shutterWidthWarning!,
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (widget.model.recommendedShutterBlade != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 14,
                              ),
                              label: Text(
                                lang == AppLanguage.french
                                    ? 'Appliquer la recommandation'
                                    : (lang == AppLanguage.english
                                        ? 'Apply recommendation'
                                        : 'تطبيق المقترح'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () async {
                                widget.model.applyRecommendedShutterBlade();
                                await widget.model.updateShutterDefaultsIfNeeded();
                                if (mounted) setState(() {});
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
                        setState(() {
                          final switchingToBelt =
                              widget.model.shutterMechanism != 'حزام';
                          widget.model.shutterMechanism = 'حزام';
                          if (switchingToBelt) {
                            widget.model.shutterDriveSide = 'left';
                          }
                        });
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
                        setState(() => widget.model.shutterMechanism = 'محرك');
                        widget.model.refreshUI();
                        unawaited(widget.model.updateShutterDefaultsIfNeeded());
                      },
                    ),
                  ],
                ),

                if (widget.model.shutterMechanism == 'محرك') ...[
                  Padding(
                    padding: EdgeInsets.only(top: 10, bottom: 5),
                    child: Text(
                      _tr('خيارات المحرك:'),
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
                        setState(() => widget.model.shutterDriveSide = 'right');
                        widget.model.refreshUI();
                      },
                    ),
                    _ContentButton(
                      label: 'يسار (Gauche)',
                      icon: Icons.keyboard_double_arrow_left,
                      selected: widget.model.shutterDriveSide == 'left',
                      onPressed: () {
                        setState(() => widget.model.shutterDriveSide = 'left');
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
                  widget.model.canUseOpeningOnlyOptions) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('استخدام بلانت أسفل الضلفة', lang),
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

              if (widget.model.hasFrameRole('seuil'))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Localization.translate('Seuil (بروفيل C)', lang)),
                  subtitle: Text(
                    widget.model.frameRoleRequiredInAllScopes('seuil')
                        ? Localization.translate('مفعل حتميًا حسب قواعد السلسلة', lang)
                        : Localization.translate('يستبدل الإطار السفلي', lang),
                  ),
                  value: widget.model.frameRoleEnabledInAnyScope('seuil'),
                  activeThumbColor: Colors.blue,
                  onChanged: widget.model.frameRoleRequiredInAllScopes('seuil')
                      ? null
                      : widget.model.toggleSeuil,
                ),

              if (widget.model.hasCaniveauSupport)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Localization.translate('تفعيل الكانيفو (Système C zéro)', lang)),
                  subtitle: Text(
                    widget.model.frameRoleEnabledInAnyScope('seuil')
                        ? Localization.translate('غير متاح مع بروفيل C / Seuil', lang)
                        : Localization.translate('يتطلب الإطار السفلي ويضيف الغطاء والبوشون تلقائياً', lang),
                  ),
                  value: widget.model.useOptionalCaniveau,
                  activeThumbColor: Colors.blue,
                  onChanged:
                      widget.model.frameRoleEnabledInAnyScope('seuil') ||
                          !widget.model.canEnableCaniveau
                      ? null
                      : widget.model.toggleCaniveau,
                ),

              if (widget.model.hasBavetteSupport)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Localization.translate('البافيت (Bavette)', lang)),
                      const SizedBox(height: 4),
                      ToggleButtons(
                        isSelected: [0, 1, 2]
                            .map(
                              (mode) =>
                                  widget.model.optionalBavetteMode == mode,
                            )
                            .toList(),
                        onPressed: widget.model.setOptionalBavetteMode,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(Localization.translate('إيقاف', lang)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(Localization.translate('أسفل فقط', lang)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(Localization.translate('الجهات الأربع', lang)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              if (widget.model.hasFrameRole('cache_dormant'))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Localization.translate('كاش الإطار (Cache dormant)', lang)),
                  subtitle: Text(
                    widget.model.frameRoleRequiredInAllScopes('cache_dormant')
                        ? Localization.translate('مفعل حتميًا حسب قواعد السلسلة', lang)
                        : Localization.translate('يتبع فقط جهات الإطار الموجودة', lang),
                  ),
                  value: widget.model.frameRoleEnabledInAnyScope(
                    'cache_dormant',
                  ),
                  activeThumbColor: Colors.blue,
                  onChanged:
                      widget.model.frameRoleRequiredInAllScopes('cache_dormant')
                      ? null
                      : widget.model.toggleCacheDormant,
                ),

              if (widget.model.hasOptionalTriangleLink &&
                  (widget.model.getConfiguredSectionForRole('triangle') !=
                          null ||
                      widget.model.getConfiguredSectionForRole(
                            'triangle',
                            useSlidingSeries: true,
                          ) !=
                          null))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Localization.translate('تراينغل (Triangle)', lang)),
                  subtitle: Text(Localization.translate('استعمال اختياري حسب ربط الأكسيسوار', lang)),
                  value: widget.model.useOptionalTriangle,
                  activeThumbColor: Colors.blue,
                  onChanged: widget.model.toggleOptionalTriangle,
                ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Localization.translate(
                            "بروفيل الزاوية 90° (Tube carré)",
                            lang,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.settings, size: 14),
                          label: Text(
                            Localization.translate('تخصيص', lang),
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => _showProfileAngleDialog(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Builder(
                      builder: (context) {
                        final junctions = widget.model
                            .getAdjacentFrameJunctions();
                        if (junctions.isNotEmpty) {
                          final active =
                              widget.model.activeProfileAngleJunctions;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: junctions.map((j) {
                                  final isSel = active.contains(j.index);
                                  return FilterChip(
                                    label: Text(
                                      j.localizedLabel(lang),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSel
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    selected: isSel,
                                    onSelected: (val) {
                                      setState(() {
                                        widget.model.toggleProfileAngleJunction(
                                          j.index,
                                          val,
                                        );
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      Localization.translate('الكل', lang),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        widget.model
                                            .setAllProfileAngleJunctions(true);
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      Localization.translate('إلغاء', lang),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        widget.model
                                            .setAllProfileAngleJunctions(false);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          );
                        }
                        return ToggleButtons(
                          isSelected: [0, 1, 2, 3]
                              .map(
                                (mode) => widget.model.profileAngleMode == mode,
                              )
                              .toList(),
                          onPressed: (index) {
                            setState(() {
                              widget.model.setProfileAngleMode(index);
                            });
                          },
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                Localization.translate('إيقاف', lang),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(Localization.translate('يمين', lang)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(Localization.translate('يسار', lang)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                Localization.translate('الجهتين', lang),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              if (widget.model.getConfiguredSectionForRole(
                    'cache_rail',
                    useSlidingSeries: true,
                  ) !=
                  null)
                Builder(
                  builder: (context) {
                    final tracks = widget.model.zones
                        .where(
                          (zone) => zone.content == ZoneContent.slidingSash,
                        )
                        .fold<int>(
                          2,
                          (current, zone) => math.max(
                            current,
                            zone.slidingTrackCount > 0
                                ? zone.slidingTrackCount
                                : zone.slidingSashesCount,
                          ),
                        );
                    final maximum = math.max(0, tracks - 1);
                    final enabled = widget.model.useOptionalCacheRail;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'كاش راي (Cache-rail)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(enabled ? 'مفعّل' : 'غير مفعّل'),
                          subtitle: Text(
                            enabled
                                ? '$tracks سكك: $maximum يمين + $maximum يسار'
                                : '$tracks سكك: لا توجد قطع كاش راي',
                          ),
                          value: enabled,
                          activeThumbColor: Colors.blue,
                          onChanged: widget.model.toggleCacheRail,
                        ),
                      ],
                    );
                  },
                ),

              if (widget.model.hasBottomFrame &&
                  widget.model.canUseOpeningOnlyOptions) ...[
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
                if (widget.model.canUseDemiOB)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Localization.translate('ديمي او بي (Demi OB)', lang),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: widget.model.effectiveUseDemiOB,
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
                    activeThumbColor: Colors.blue,
                    onChanged: (value) {
                      widget.model.toggleVerrouCentral(value);
                    },
                  ),
              ],

              if (!_pvcMontantReinforcementDisabled) ...[
                const Divider(height: 30),

                // 🟢 2. قسم تدعيم المونطو (يظهر دائماً في الأسفل)
                // 🟢 هذا الجزء يحل مشكلة تدعيم المونطو (Renfort)
                Text(
                  Localization.translate('تدعيم المونطو والأعمدة (Renfort)', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),

                Builder(
                  builder: (context) {
                    final montantProfiles = <Map<String, dynamic>>[
                      ..._sashProfiles,
                      ..._slidingSashProfiles,
                      ...?(widget.model.effectiveSlidingSeries ??
                              widget.model.activeSlidingSeries)
                          ?.sections
                          .map((section) => section.toMap()),
                    ];
                    final bool isSupported = montantProfiles.any(
                      (item) =>
                          _isSlidingMontantCandidate(item, central: false) ||
                          _isSlidingMontantCandidate(item, central: true),
                    );

                    final bool hasThreePiece =
                        (widget.model.effectiveSlidingSeries?.hasThreePieceSash ??
                            widget.model.activeSlidingSeries?.hasThreePieceSash ??
                            false) ||
                        '${widget.model.effectiveSlidingSeries?.name ?? widget.model.activeSlidingSeries?.name ?? ''}'
                            .toLowerCase()
                            .contains('tpr');

                    // 2. إذا كانت السلسلة فيها مونطو منزلق (3 قطع) أو تم اختيار عمود مستقل ببراغي
                    if (hasThreePiece &&
                        (isSupported ||
                            widget.model.reinforcementMode ==
                                ReinforcementMode.independentScrewed) &&
                        firstSlidingZone != null) {
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
                          Builder(
                            builder: (context) {
                              final linkedCentral =
                                  widget
                                      .model
                                      .componentOverrides['قائم وسطي معزز (Sash Central Renforcé)']?['name'] ??
                                  widget
                                      .model
                                      .componentOverrides['قائم وسطي (Sash Central)']?['name'] ??
                                  widget.model
                                      .getSlidingSectionByType(
                                        'sash_central_reinforced',
                                      )
                                      ?.name ??
                                  widget.model
                                      .getSlidingSectionByType(
                                        'chicane_renforcee',
                                      )
                                      ?.name ??
                                  widget.model
                                      .getSlidingSectionByType('chicane')
                                      ?.name;
                              if (linkedCentral != null &&
                                  linkedCentral.toString().isNotEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${Localization.translate('البروفيل:', lang)} $linkedCentral',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          Wrap(
                            children: List.generate(centralCount, (index) {
                              return SizedBox(
                                width: 120,
                                child: buildCompactOption(
                                  '${Localization.translate('مركز', lang)} ${index + 1}',
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
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                          ),
                        ),
                      );
                    }
                    // 4. إذا لم يكن هناك نظام منزلق أصلاً
                    else {
                      return const SizedBox.shrink();
                    }
                  },
                ),

                const Divider(height: 30),
                Text(
                  Localization.translate('مونتوسليم (Montant Slim)', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),

                Builder(
                  builder: (context) {
                    final slimCandidates = widget.model
                        .getSlidingSlimCandidates();
                    if (slimCandidates.isNotEmpty && firstSlidingZone != null) {
                      final allSlimSelected =
                          List.generate(
                            centralCount,
                            (i) => 'central_$i',
                          ).every(
                            (k) =>
                                firstSlidingZone.slidingMontantSlim[k] == true,
                          );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                Localization.translate(
                                  'المركزي (Central):',
                                  lang,
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: Icon(
                                  allSlimSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 16,
                                ),
                                label: Text(
                                  allSlimSelected
                                      ? Localization.translate(
                                          'إلغاء الكل',
                                          lang,
                                        )
                                      : Localization.translate(
                                          'تحديد الكل',
                                          lang,
                                        ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  setState(() {
                                    final newVal = !allSlimSelected;
                                    for (int i = 0; i < centralCount; i++) {
                                      firstSlidingZone
                                              .slidingMontantSlim['central_$i'] =
                                          newVal;
                                    }
                                    if (newVal &&
                                        widget
                                                .model
                                                .selectedSlimMontantProfile ==
                                            null) {
                                      widget.model
                                          .applySlidingMontantSlimOverride(
                                            slimCandidates.first,
                                          );
                                    }
                                  });
                                  widget.model.refreshUI();
                                },
                              ),
                            ],
                          ),
                          Wrap(
                            children: List.generate(centralCount, (index) {
                              return SizedBox(
                                width: 120,
                                child: buildCompactSlimOption(
                                  '${Localization.translate('مركز', lang)} ${index + 1}',
                                  'central_$index',
                                  firstSlidingZone,
                                ),
                              );
                            }),
                          ),
                        ],
                      );
                    } else if (firstSlidingZone != null) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          Localization.translate(
                            'هذه السلسلة لا تدعم مونتوسليم',
                            lang,
                          ),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  },
                ),
              ],
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
      currentValue = _shownDoubleSashCuttingWidth(zone, 1.0 - effectiveRatio);
      title = 'تعديل عرض الدلفة اليمنى';
    } else {
      currentValue = hit.isWidth ? zone.boundary.width : zone.boundary.height;
      title = hit.isWidth ? 'تعديل عرض التقسيم' : 'تعديل ارتفاع التقسيم';
    }

    final ctrl = TextEditingController(text: _shownDimensionText(currentValue));
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: Localization.translate('القياس الداخلي (mm)', lang),
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
                    final totalCutWidth =
                        zone.boundary.width +
                        _openingSashOverlapForDrawing() * 2;
                    final visualLeftRatio =
                        (hit.isDoubleSashLeft
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

  /// Shows outer-dimension dialog for a single frame in a coupled window.
  void _showFrameResizeDialog(BuildContext context, InnerDimensionHit hit) {
    final zone = widget.model.zones.firstWhere((z) => z.id == hit.zoneId);
    final double pt = widget.model.profileThickness;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    double outerVal;
    String title;
    if (hit.isWidth) {
      outerVal =
          widget.model.frameRectForZone(hit.zoneId)?.width ??
          zone.boundary.width + 2 * pt;
      title = 'تعديل عرض الإطار (خارجي)';
    } else {
      outerVal =
          widget.model.frameRectForZone(hit.zoneId)?.height ??
          zone.boundary.height + 2 * pt;
      title = 'تعديل ارتفاع الإطار (خارجي)';
    }
    final ctrl = TextEditingController(text: outerVal.toInt().toString());
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
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
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: Localization.translate(
                hit.isWidth ? 'العرض الخارجي (mm)' : 'الارتفاع الخارجي (mm)',
                lang,
              ),
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
              onPressed: () {
                final val = double.tryParse(ctrl.text);
                if (val != null && val >= 200) {
                  widget.model.resizeFrameOuterDimensionForZone(
                    hit.zoneId,
                    isWidth: hit.isWidth,
                    outerSize: val,
                  );
                }
                Navigator.pop(ctx);
              },
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

  Future<void> _showDesktopContextMenu(
    BuildContext context,
    Offset globalPosition,
    Offset localPosition,
  ) async {
    final modelPos = _getModelPos(localPosition);

    // 1. Check if shutter is clicked
    if (widget.model.hasShutter) {
      final double shutterTop = -widget.model.shutterBoxHeight;
      final double shutterBottom = widget.model.topSlantLeftY;
      if (modelPos.dy >= shutterTop - 20 &&
          modelPos.dy <= shutterBottom + 10 &&
          modelPos.dx >= -20 &&
          modelPos.dx <= widget.model.width + 20) {
        setState(() {
          _isShutterSelected = true;
          _activeShutterTab = 0;
          widget.model.clearSelection();
        });
      }
    }

    final frameAtBorder = _frameAtBorder(modelPos);
    if (frameAtBorder != null) {
      setState(() {
        _isShutterSelected = false;
      });
      widget.model.selectFrameByIndex(frameAtBorder);
    } else if (!_isShutterSelected) {
      setState(() {
        _isShutterSelected = false;
      });
      widget.model.selectAt(modelPos, isLongPress: false);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedZone = widget.model.selectedZone;
    final isFrame = widget.model.selection.type == SelectionType.frame;

    final selectedValue = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      color: isDark ? const Color(0xFF252536) : Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDark ? Colors.white24 : Colors.grey.shade300,
          width: 0.8,
        ),
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Row(
            children: [
              Icon(
                _isShutterSelected
                    ? Icons.menu_rounded
                    : (isFrame
                          ? Icons.crop_square_rounded
                          : Icons.window_rounded),
                size: 16,
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                _isShutterSelected
                    ? 'خصائص الستار'
                    : (isFrame ? 'خصائص الإطار' : 'خصائص المنطقة والضلفة'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),

        if (selectedZone != null && !_isShutterSelected && !isFrame) ...[
          _buildContextMenuItem(
            value: 'content_fixe',
            icon: Icons.crop_landscape_rounded,
            label: 'زجاج ثابت (Fixe)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_single_sash',
            icon: Icons.sensor_door_outlined,
            label: 'ضلفة عادية (Ouvrant Simple)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_double_sash',
            icon: Icons.door_sliding_outlined,
            label: 'ضلفة فرنسية مزدوجة (Double Ouvrant)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_sliding_2',
            icon: Icons.compare_arrows_rounded,
            label: 'منزلق 2 ضلف (Coulissant 2 Vantaux)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_sliding_3',
            icon: Icons.view_column_rounded,
            label: 'منزلق 3 ضلف (Coulissant 3 Vantaux)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_sliding_4',
            icon: Icons.grid_view_rounded,
            label: 'منزلق 4 ضلف (Coulissant 4 Vantaux)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_vide',
            icon: Icons.check_box_outline_blank_rounded,
            label: 'تفريغ (Vide)',
            isDark: isDark,
          ),
          const PopupMenuDivider(height: 1),

          _buildContextMenuItem(
            value: 'add_h_division',
            icon: Icons.border_horizontal_rounded,
            label: 'إضافة قاطع أفقي (+ Traverse)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'add_v_division',
            icon: Icons.border_vertical_rounded,
            label: 'إضافة قاطع عمودي (+ Montant)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'clear_divisions',
            icon: Icons.layers_clear_rounded,
            label: 'مسح القواطع الداخلية',
            isDark: isDark,
          ),
          const PopupMenuDivider(height: 1),

          _buildContextMenuItem(
            value: 'customize_glass',
            icon: Icons.view_in_ar_rounded,
            label: 'تخصيص نوع الزجاج والبانو...',
            isDark: isDark,
          ),

          if (selectedZone.content == ZoneContent.singleSash) ...[
            _buildContextMenuItem(
              value: 'sash_dir_right',
              icon: Icons.arrow_forward_rounded,
              label: 'فتح إلى اليمين (Droite)',
              isDark: isDark,
            ),
            _buildContextMenuItem(
              value: 'sash_dir_left',
              icon: Icons.arrow_back_rounded,
              label: 'فتح إلى اليسار (Gauche)',
              isDark: isDark,
            ),
            _buildContextMenuItem(
              value: 'sash_dir_top',
              icon: Icons.arrow_upward_rounded,
              label: 'سوفلي / فتح لأعلى (Vasistas/Haut)',
              isDark: isDark,
            ),
            _buildContextMenuItem(
              value: 'sash_dir_bottom',
              icon: Icons.arrow_downward_rounded,
              label: 'فتح لأسفل (Bas)',
              isDark: isDark,
            ),
          ],
        ],

        if (isFrame) ...[
          _buildContextMenuItem(
            value: 'frame_delete',
            icon: Icons.delete_outline_rounded,
            label: 'حذف هذا الإطار',
            color: Colors.redAccent,
            isDark: isDark,
          ),
        ],

        if (_isShutterSelected) ...[
          _buildContextMenuItem(
            value: 'shutter_open_options',
            icon: Icons.tune_rounded,
            label: 'إعدادات الستار والمحرك...',
            isDark: isDark,
          ),
        ],

        const PopupMenuDivider(height: 1),

        _buildContextMenuItem(
          value: 'undo',
          icon: Icons.undo_rounded,
          label: 'تراجع (Undo)',
          enabled: widget.model.canUndo,
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'redo',
          icon: Icons.redo_rounded,
          label: 'إعادة (Redo)',
          enabled: widget.model.canRedo,
          isDark: isDark,
        ),
      ],
    );

    if (selectedValue == null) return;

    switch (selectedValue) {
      case 'content_fixe':
        if (selectedZone != null)
          _paintZoneContentFromUi(selectedZone, ZoneContent.fixedGlass);
        break;
      case 'content_single_sash':
        if (selectedZone != null)
          _paintZoneContentFromUi(selectedZone, ZoneContent.singleSash);
        break;
      case 'content_double_sash':
        if (selectedZone != null)
          _paintZoneContentFromUi(selectedZone, ZoneContent.doubleSash);
        break;
      case 'content_sliding_2':
        if (selectedZone != null)
          _paintZoneContentFromUi(
            selectedZone,
            ZoneContent.slidingSash,
            slidingSashesCount: 2,
          );
        break;
      case 'content_sliding_3':
        if (selectedZone != null)
          _paintZoneContentFromUi(
            selectedZone,
            ZoneContent.slidingSash,
            slidingSashesCount: 3,
          );
        break;
      case 'content_sliding_4':
        if (selectedZone != null)
          _paintZoneContentFromUi(
            selectedZone,
            ZoneContent.slidingSash,
            slidingSashesCount: 4,
          );
        break;
      case 'content_vide':
        if (selectedZone != null)
          _paintZoneContentFromUi(selectedZone, ZoneContent.empty);
        break;
      case 'add_h_division':
        if (selectedZone != null) {
          selectedZone.innerH += 1;
          selectedZone.innerHPositions = const [];
          widget.model.refreshUI();
        }
        break;
      case 'add_v_division':
        if (selectedZone != null) {
          selectedZone.innerV += 1;
          selectedZone.innerVPositions = const [];
          widget.model.refreshUI();
        }
        break;
      case 'clear_divisions':
        if (selectedZone != null) {
          selectedZone.innerH = 0;
          selectedZone.innerV = 0;
          selectedZone.rightInnerH = 0;
          selectedZone.rightInnerV = 0;
          selectedZone.innerHPositions = const [];
          selectedZone.innerVPositions = const [];
          selectedZone.rightInnerHPositions = const [];
          selectedZone.rightInnerVPositions = const [];
          widget.model.refreshUI();
        }
        break;
      case 'customize_glass':
        setState(() {
          _isBottomPanelExpanded = true;
          _activeBottomTab = 2;
        });
        break;
      case 'sash_dir_right':
        widget.model.setSelectedZoneOpenDirection(OpenDirection.right);
        break;
      case 'sash_dir_left':
        widget.model.setSelectedZoneOpenDirection(OpenDirection.left);
        break;
      case 'sash_dir_top':
        widget.model.setSelectedZoneOpenDirection(OpenDirection.top);
        break;
      case 'sash_dir_bottom':
        widget.model.setSelectedZoneOpenDirection(OpenDirection.bottom);
        break;
      case 'frame_delete':
        widget.model.deleteSelectedFrame();
        break;
      case 'shutter_open_options':
        setState(() {
          _isShutterSelected = true;
          _isBottomPanelExpanded = true;
          _activeShutterTab = 0;
        });
        break;
      case 'undo':
        widget.model.undo();
        if (_isShutterSelected &&
            !widget.model.isShutterOnly &&
            (widget.model.zones.isNotEmpty || !widget.model.hasShutter)) {
          setState(() {
            _isShutterSelected = false;
          });
        }
        break;
      case 'redo':
        widget.model.redo();
        if (widget.model.isShutterOnly && !_isShutterSelected) {
          setState(() {
            _isShutterSelected = true;
          });
        }
        break;
    }
  }

  PopupMenuItem<String> _buildContextMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required bool isDark,
    bool enabled = true,
    Color? color,
  }) {
    final itemColor =
        color ??
        (enabled ? (isDark ? Colors.white : Colors.black87) : Colors.grey);
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 18, color: itemColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Localization.translate(
                label,
                Provider.of<AppSettingsProvider>(
                  context,
                  listen: false,
                ).language,
              ),
              style: TextStyle(
                fontSize: 13,
                color: itemColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showResizeDialog(BuildContext context, {required bool focusWidth}) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final widthCtrl = TextEditingController(
      text: widget.model.width > 0 ? widget.model.width.toInt().toString() : '',
    );
    final heightCtrl = TextEditingController(
      text: widget.model.height > 0
          ? widget.model.height.toInt().toString()
          : '',
    );
    final heightFocus = FocusNode();
    BuildContext? dialogContext;
    void apply() {
      final w = double.tryParse(widthCtrl.text);
      final h = double.tryParse(heightCtrl.text);
      if (w == null ||
          h == null ||
          w < widget.model.profileThickness * 3 ||
          h < widget.model.profileThickness * 3)
        return;
      widget.model.resizeWindow(w, h);
      // `context` here belongs to the drawing route. Popping it returns the
      // user to the system selector instead of dismissing this dialog.
      final activeDialogContext = dialogContext;
      if (activeDialogContext != null) {
        Navigator.of(activeDialogContext, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        dialogContext = context;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            Localization.translate('تعديل قياسات النافذة', lang),
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
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onChanged: (value) {
                    if (value.length == 4) {
                      heightFocus.requestFocus();
                      heightCtrl.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: heightCtrl.text.length,
                      );
                    }
                  },
                  onSubmitted: (_) => apply(),
                  autofocus: focusWidth,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'العرض الإجمالي (mm)',
                      lang,
                    ),
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
                  focusNode: heightFocus,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onSubmitted: (_) => apply(),
                  autofocus: !focusWidth,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'الارتفاع الإجمالي (mm)',
                      lang,
                    ),
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
              onPressed: apply,
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

  List<Map<String, dynamic>> _availableMullionFrameSections() {
    final frames = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    double readDimension(Map<String, dynamic> raw, String key) {
      final value = raw[key];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    void addFrame(Map<String, dynamic> raw) {
      final code = (raw['code'] ?? '').toString().trim();
      final name = (raw['name'] ?? '').toString().trim();
      final type = (raw['type'] ?? '').toString().toLowerCase();
      final isFrameFlag =
          raw['is_frame'] == 1 ||
          raw['isFrame'] == true ||
          raw['is_frame']?.toString() == '1';
      final isFrame =
          isFrameFlag ||
          type == 'frame' ||
          type == 'cadre' ||
          type == 'dormant' ||
          type == 'إطار';
      if (!isFrame) return;
      final coverWidth = readDimension(raw, 'couvre_joint_width');
      final hasIntegratedCover =
          coverWidth > 0.5 ||
          name.toLowerCase().contains('مدمج') ||
          name.toLowerCase().contains('intégré') ||
          name.toLowerCase().contains('integre') ||
          name.toLowerCase().contains('monobloc') ||
          type.contains('monobloc');
      if (hasIntegratedCover) return;
      final idKey = (raw['id'] ?? '$code:$name').toString();
      if (!seenIds.add(idKey)) return;
      frames.add(Map<String, dynamic>.from(raw));
    }

    for (final frame in _frameProfiles) {
      addFrame(frame);
    }

    frames.sort((a, b) {
      final aCode = (a['code'] ?? '').toString();
      final bCode = (b['code'] ?? '').toString();
      return aCode.compareTo(bCode);
    });
    return frames;
  }

  bool _selectedMullionFrameMatches(
    Map<String, dynamic> frame,
    MullionProfileType type,
  ) {
    final selection = widget.model.selection;
    if (selection.type != SelectionType.mullion ||
        selection.isHorizontalMullion == null ||
        selection.mullionPosition == null) {
      return false;
    }
    final key =
        '${selection.isHorizontalMullion! ? 'H' : 'V'}_${selection.mullionPosition!.toStringAsFixed(1)}';
    final currentType =
        widget.model.mullionProfiles[key] ?? MullionProfileType.standard;
    final current = widget.model.mullionSectionOverrides[key];
    if (currentType != type || current == null) return false;
    return current['id']?.toString() == frame['id']?.toString();
  }

  Future<void> _applyMullionFrameSection(
    MullionProfileType type,
    Map<String, dynamic> frame,
  ) async {
    final mutable = Map<String, dynamic>.from(frame);
    mutable['calculated_price'] = await _sectionPriceForSelectedColor(mutable);
    if (!mounted) return;
    setState(() {
      widget.model.setMullionFrameSection(type, mutable);
    });
  }

  Future<void> _showMullionFrameSelectorDialog(
    BuildContext context,
    MullionProfileType type,
  ) async {
    final frames = _availableMullionFrameSections();
    final title = type == MullionProfileType.flat
        ? 'Cadre doublé - اختر إطار التقسيم'
        : 'Cadre مفرد / 140 - اختر إطار التقسيم';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          if (frames.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                _tr('لا توجد إطارات متوفرة لهذه السلسلة'),
                textDirection: TextDirection.rtl,
              ),
            )
          else
            ...frames.map((frame) {
              final code = (frame['code'] ?? '').toString();
              final name = (frame['name'] ?? 'بدون اسم').toString();
              final label = code.isEmpty ? name : '$code - $name';
              final selected = _selectedMullionFrameMatches(frame, type);
              return SimpleDialogOption(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _applyMullionFrameSection(type, frame);
                },
                child: Row(
                  children: [
                    SectionImageWidget(
                      code: code,
                      name: name,
                      imagePath: frame['image_path']?.toString(),
                      size: 28,
                      fallbackIcon: type == MullionProfileType.flat
                          ? Icons.splitscreen_rounded
                          : Icons.view_headline_rounded,
                      fallbackColor: selected
                          ? Colors.blue.shade700
                          : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label)),
                    if (selected)
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showMullionTypeDialog(BuildContext context) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
          Navigator.pop(context);
          if (type == MullionProfileType.standard) {
            widget.model.setMullionProfile(type);
          } else {
            unawaited(_showMullionFrameSelectorDialog(context, type));
          }
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
            if (type != MullionProfileType.standard)
              const Icon(Icons.chevron_right_rounded, color: Colors.blueGrey),
            if (type == currentType)
              Icon(Icons.check_circle, color: Colors.green.shade700),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(Localization.translate('نوع التقسيم', lang)),
        children: [
          typeOption(
            MullionProfileType.standard,
            Localization.translate('Traverse — تقسيم عادي', lang),
            Icons.horizontal_rule_rounded,
          ),
          typeOption(
            MullionProfileType.flat,
            Localization.translate('Cadre double — إطار مزدوج', lang),
            Icons.splitscreen_rounded,
          ),
          typeOption(
            MullionProfileType.grooved,
            Localization.translate('Cadre 140 — إطار بتجويف واحد', lang),
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
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(Localization.translate('عكس اتجاه التجويف', lang)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMullionToolbar(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String key =
        "${widget.model.selection.isHorizontalMullion! ? 'H' : 'V'}_${widget.model.selection.mullionPosition!.toStringAsFixed(1)}";
    MullionProfileType currentType =
        widget.model.mullionProfiles[key] ?? MullionProfileType.standard;
    Widget toolbarButton({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onPressed,
      bool showSubmenuIndicator = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(
              color: selected ? Colors.white : Colors.white38,
              width: selected ? 1.6 : 1.0,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          icon: Icon(icon, size: 16),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              if (showSubmenuIndicator) ...[
                const SizedBox(width: 3),
                const Icon(Icons.chevron_right_rounded, size: 15),
              ],
            ],
          ),
          onPressed: onPressed,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.blue.shade900.withValues(alpha: 0.85),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_indicator_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              Localization.translate('العمود محدد', lang),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 12),
            toolbarButton(
              label: 'Traverse',
              icon: Icons.horizontal_rule_rounded,
              selected: currentType == MullionProfileType.standard,
              onPressed: () =>
                  widget.model.setMullionProfile(MullionProfileType.standard),
            ),
            toolbarButton(
              label: 'Cadre doublé',
              icon: Icons.splitscreen_rounded,
              selected: currentType == MullionProfileType.flat,
              showSubmenuIndicator: true,
              onPressed: () => _showMullionFrameSelectorDialog(
                context,
                MullionProfileType.flat,
              ),
            ),
            toolbarButton(
              label: 'Cadre 140',
              icon: Icons.view_headline_rounded,
              selected: currentType == MullionProfileType.grooved,
              showSubmenuIndicator: true,
              onPressed: () => _showMullionFrameSelectorDialog(
                context,
                MullionProfileType.grooved,
              ),
            ),
            if (currentType == MullionProfileType.grooved)
              toolbarButton(
                label: Localization.translate('قلب الجهة', lang),
                icon: Icons.swap_horiz_rounded,
                selected: widget.model.isGroovedMullionCavityOnPositiveSide(
                  widget.model.selection.isHorizontalMullion!,
                  widget.model.selection.mullionPosition!,
                ),
                onPressed: () => widget.model.toggleGroovedMullionCavity(
                  widget.model.selection.isHorizontalMullion!,
                  widget.model.selection.mullionPosition!,
                ),
              ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              icon: const Icon(
                Icons.delete_sweep,
                color: Colors.white,
                size: 16,
              ),
              label: Text(
                Localization.translate('حذف', lang),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              onPressed: () => widget.model.deleteSelectedMullion(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInnerDivisionToolbar(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.blue.shade900.withValues(alpha: 0.8),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            Localization.translate('التقسيم محدد (اسحب للتحريك)', lang),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 18),
            label: Text(
              Localization.translate('حذف', lang),
              style: const TextStyle(color: Colors.white),
            ),
            onPressed: () => widget.model.deleteSelectedInnerDivision(),
          ),
        ],
      ),
    );
  }

  Widget _buildFrameToolbar(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.indigo.shade900.withValues(alpha: 0.85),
      child: Row(
        children: [
          const Icon(Icons.crop_square_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            Localization.translate('الإطار محدد', lang),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (widget.model.getFrameRects().length > 1)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              icon: const Icon(
                Icons.delete_sweep,
                color: Colors.white,
                size: 18,
              ),
              label: Text(
                Localization.translate('حذف الإطار', lang),
                style: const TextStyle(color: Colors.white),
              ),
              onPressed: () => widget.model.deleteSelectedFrame(),
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
      return Tooltip(
        message: Localization.translate(
          'ضغطة للتفعيل أو التعطيل، واضغط مطولا لتخصيص الغطاء',
          lang,
        ),
        child: Stack(
          children: [
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(labelFor(side)),
              selected: enabled,
              onSelected: (_) {},
            ),
            // This transparent layer is deliberately above the chip so one
            // recognizer owns both gestures. It makes a short tap reliable
            // on touch screens and desktop while preserving long press and
            // right-click for the segment editor.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => model.toggleSideCoverSegment(side),
                onLongPress: () => _showSideCoverSegmentDialog(context, side),
                onSecondaryTap: () =>
                    _showSideCoverSegmentDialog(context, side),
              ),
            ),
          ],
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
    // Long-press callbacks can finish after WindowView has been removed
    // (for example when the user confirms another dialog or leaves the page).
    // Keep one live page context and never use the callback's stale context
    // after an async dialog returns.
    if (!mounted || !context.mounted) return;
    final pageContext = this.context;
    final model = widget.model;
    final lang = Provider.of<AppSettingsProvider>(
      pageContext,
      listen: false,
    ).language;
    final sideLength = model.sideCoverSideLength(side);
    if (sideLength <= 0) return;

    final existing = model.sideCoverSegmentForSide(side);
    final vertical = side == 'left' || side == 'right';
    final leading = vertical ? 'الأعلى' : 'اليسار';
    final trailing = vertical ? 'الأسفل' : 'اليمين';
    final sideLabel = vertical
        ? (side == 'right' ? 'اليمنى' : 'اليسرى')
        : (side == 'top' ? 'العلوية' : 'السفلية');
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
    SideCoverSegment? segmentToSave;
    bool removeExistingSegment = false;

    double readValue(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? -1;

    try {
      await showDialog<void>(
        context: pageContext,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final startLabel = fromTrailing ? trailing : leading;
            final endLabel = fromTrailing ? leading : trailing;
            return AlertDialog(
              title: Text(
                '${Localization.translate('تخصيص غطاء الجهة', lang)} ${Localization.translate(sideLabel, lang)}',
              ),
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
                            label: Text(
                              '${Localization.translate('من', lang)} ${Localization.translate(leading, lang)}',
                            ),
                            selected: !fromTrailing,
                            onSelected: (_) => setDialogState(() {
                              fromTrailing = false;
                            }),
                          ),
                          ChoiceChip(
                            label: Text(
                              '${Localization.translate('من', lang)} ${Localization.translate(trailing, lang)}',
                            ),
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
                        title: Text(
                          Localization.translate(
                            'إدخال النهاية بدل الطول',
                            lang,
                          ),
                        ),
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
                          labelText:
                              '${Localization.translate('بداية الغطاء من', lang)} ${Localization.translate(startLabel, lang)} (${Localization.translate('مم', lang)})',
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
                              ? '${Localization.translate('نهاية الغطاء قبل', lang)} ${Localization.translate(endLabel, lang)} (${Localization.translate('مم', lang)})'
                              : Localization.translate(
                                  'طول الغطاء على الإطار (مم)',
                                  lang,
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: visibleController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'العرض الظاهر خارج الإطار (مم)',
                            lang,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${Localization.translate('طول الجهة:', lang)} ${sideLength.toStringAsFixed(0)} ${Localization.translate('مم', lang)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () {
                      if (!dialogContext.mounted) return;
                      removeExistingSegment = true;
                      Navigator.of(dialogContext).pop();
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: Text(
                      Localization.translate('حذف', lang),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: Text(Localization.translate('إلغاء', lang)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final first = readValue(startController);
                    final second = readValue(secondController);
                    final visible = readValue(visibleController);
                    if (first < 0 || second < 0 || visible < 0) {
                      if (pageContext.mounted) {
                        ScaffoldMessenger.maybeOf(pageContext)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate('أدخل قياسات صحيحة', lang),
                            ),
                          ),
                        );
                      }
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
                      if (pageContext.mounted) {
                        ScaffoldMessenger.maybeOf(pageContext)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate(
                                'يجب أن تكون نهاية الغطاء بعد بدايته',
                                lang,
                              ),
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    if (!mounted || !dialogContext.mounted) return;
                    segmentToSave = SideCoverSegment(
                      side: side,
                      startOffset: start,
                      endOffset: end,
                      visibleWidth: visible,
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(Localization.translate('حفظ', lang)),
                ),
              ],
            );
          },
        ),
      );

      // `showDialog` completes when Navigator.pop is called, while the dialog
      // widgets can remain mounted during the reverse route animation. Do not
      // notify the drawing model in that interval: rebuilding the page would
      // make inherited-context lookups run from a deactivating dialog tree.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      if (removeExistingSegment) {
        model.removeSideCoverSegment(side);
      } else if (segmentToSave != null) {
        model.saveSideCoverSegment(segmentToSave!);
      }
    } finally {
      startController.dispose();
      secondController.dispose();
      visibleController.dispose();
    }
  }

  Widget buildShutterSidesControl(
    BuildContext context,
    WindowModel model,
    AppLanguage lang,
  ) {
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

  Future<void> _showDrawingDefaultSeriesDialog() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String t(String value) => Localization.translate(value, lang);
    final opening = <int, AluminumSeries>{};
    final sliding = <int, AluminumSeries>{};
    for (final system in widget.model.availableSystems) {
      for (final series in _seriesForScope(system, 'opening')) {
        opening[series.id] = series;
      }
      for (final series in _seriesForScope(system, 'sliding')) {
        sliding[series.id] = series;
      }
    }
    int? openingId = prefs.getInt('default_opening_series_id');
    int? slidingId = prefs.getInt('default_sliding_series_id');
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Widget selector(
            String label,
            Map<int, AluminumSeries> items,
            int? selected,
            ValueChanged<int?> changed,
          ) {
            return DropdownButtonFormField<int>(
              value: items.containsKey(selected) ? selected : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: t(label)),
              hint: Text(t('تلقائي (افتراضي النظام)')),
              items: items.values
                  .map(
                    (series) => DropdownMenuItem<int>(
                      value: series.id,
                      child: Text(series.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: saving ? null : changed,
            );
          }

          return AlertDialog(
            title: Text(t('السلاسل الافتراضية للورشة')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('اختر السلاسل للنوافذ الجديدة. لن يتغير الرسم الحالي.'),
                    ),
                    const SizedBox(height: 16),
                    selector(
                      'سلسلة الفتح الافتراضية (Battant):',
                      opening,
                      openingId,
                      (value) => update(() => openingId = value),
                    ),
                    const SizedBox(height: 16),
                    selector(
                      'سلسلة المنزلق الافتراضية (Coulissant):',
                      sliding,
                      slidingId,
                      (value) => update(() => slidingId = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(t('إلغاء')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        update(() => saving = true);
                        if (openingId != null) {
                          await prefs.setInt(
                            'default_opening_series_id',
                            openingId!,
                          );
                        }
                        if (slidingId != null) {
                          await prefs.setInt(
                            'default_sliding_series_id',
                            slidingId!,
                          );
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                child: Text(t('حفظ')),
              ),
            ],
          );
        },
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isStandaloneShutterContext =
        widget.model.isShutterOnly || widget.model.drawNextShapeAsShutterOnly;
    final isShutterContext = isStandaloneShutterContext || _isShutterSelected;
    final rawShutterColorItems =
        widget.model.availableAccessoryColors.isNotEmpty
        ? widget.model.availableAccessoryColors
        : widget.model.availableColors;
    final shutterColorItems = <Map<String, dynamic>>[];
    final seenShutterColorIds = <String>{};
    for (final c in rawShutterColorItems) {
      final idStr = (c['id'] ?? c['name'] ?? '').toString();
      if (idStr.isNotEmpty && seenShutterColorIds.add(idStr)) {
        shutterColorItems.add(c);
      }
    }
    final selectedShutterColorId = widget.model.effectiveShutterColor?['id']
        ?.toString();
    final selectedShutterColor =
        (selectedShutterColorId != null &&
            shutterColorItems.any(
              (color) => color['id']?.toString() == selectedShutterColorId,
            ))
        ? shutterColorItems.firstWhere(
            (color) => color['id']?.toString() == selectedShutterColorId,
          )
        : null;
    // The selectors describe the drawing itself, not the route that happened
    // to open it. An edited sliding-only drawing can arrive through the
    // mixed editor route, so using `widget.systemMode` here showed the false
    // hints "سلسلة الفتح / Gamme coulissant" instead of its saved BS90.
    final hasSlidingDrawing = widget.model.zones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpeningDrawing = widget.model.zones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash ||
          (hasSlidingDrawing &&
              (zone.content == ZoneContent.empty ||
                  zone.content == ZoneContent.fixedGlass)),
    );
    final isSlidingOnlyDrawing = hasSlidingDrawing && !hasOpeningDrawing;
    final isOpeningOnlyDrawing = hasOpeningDrawing && !hasSlidingDrawing;
    final isMixedDrawing = hasSlidingDrawing && hasOpeningDrawing;
    final isInitialOrEmptyDrawing = !hasOpeningDrawing && !hasSlidingDrawing;

    // Once the canvas contains opening or both constructions, the first selector
    // is always the opening-series selector. Only when the drawing contains exclusively
    // sliding sashes does the first selector become the sliding one.
    final selectorShowsSliding = isSlidingOnlyDrawing;

    // The first selector is the real frame-owning series. A second selector
    // exists when the canvas contains both opening and sliding, or in the initial state
    // so the user can choose either opening or sliding from the start.
    var primarySeries = selectorShowsSliding
        ? widget.model.activeSlidingSeries
        : widget.model.activeSeries;
    // Adding an opening frame to a saved sliding drawing must initialize its
    // counterpart without replacing the series already used by that drawing.
    if (!selectorShowsSliding && primarySeries == null && isMixedDrawing) {
      final owner = profileSystemForSeries(
        widget.model.availableSystems,
        widget.model.activeSlidingSeries,
      );
      final candidates = owner == null
          ? <AluminumSeries>[]
          : _seriesForScope(owner, 'opening').toList();
      if (candidates.isNotEmpty) {
        primarySeries = candidates.first;
        if (!_openingSeriesAutoSelectionQueued) {
          _openingSeriesAutoSelectionQueued = true;
          final candidate = candidates.first;
          final slidingId = widget.model.activeSlidingSeries?.id;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              if (mounted &&
                  widget.model.activeSeries == null &&
                  widget.model.activeSlidingSeries?.id == slidingId) {
                widget.model.systemMode = 'mixed';
                await widget.model.setActiveSeries(candidate);
              }
            } finally {
              _openingSeriesAutoSelectionQueued = false;
            }
          });
        }
      }
    }
    final primarySystem = profileSystemForSeries(
      widget.model.availableSystems,
      primarySeries,
    );
    final primaryItemsList = () {
      final List<AluminumSeries> list = [];
      for (var system in widget.model.availableSystems) {
        list.addAll(
          _seriesForScope(system, selectorShowsSliding ? 'sliding' : 'opening'),
        );
      }
      // Keep a selected legacy series visible only when it belongs to the
      // selector's mode. Never reinsert a series from the other mode.
      final selectedPrimarySeries = primarySeries;
      final primaryMatchesMode =
          selectedPrimarySeries != null &&
          (selectorShowsSliding
              ? primarySystem != null &&
                    _seriesMatchesScope(
                      selectedPrimarySeries,
                      primarySystem,
                      'sliding',
                    )
              : primarySystem != null &&
                    _seriesMatchesScope(
                      selectedPrimarySeries,
                      primarySystem,
                      'opening',
                    ));
      if (selectedPrimarySeries != null &&
          primaryMatchesMode &&
          !list.any((s) => s.id == selectedPrimarySeries.id)) {
        list.add(selectedPrimarySeries);
      }

      final uniqueList = <AluminumSeries>[];
      for (final s in list) {
        if (!uniqueList.any((existing) => existing.id == s.id)) {
          uniqueList.add(s);
        }
      }
      return uniqueList;
    }();

    final primarySeriesId = primarySeries?.id;
    final safePrimaryValue =
        (primarySeriesId != null &&
            primaryItemsList.any((s) => s.id == primarySeriesId))
        ? primaryItemsList.firstWhere((s) => s.id == primarySeriesId)
        : null;

    final slidingItemsList = () {
      // The selector must use the same role/scope rule as the model.  The
      // system name is commercial data, so it must not be used to classify a
      // series as opening or sliding.
      final List<AluminumSeries> list = [];
      if (primarySystem != null) {
        // Resolve the list directly from the selected opening series' system.
        // This guarantees that choosing one of several opening series never
        // falls back to sliding rows from another system with the same
        // material or a similar commercial name.
        list.addAll(
          _seriesForScope(
            primarySystem,
            'sliding',
          ).where((series) => series.id != primarySeries?.id),
        );
      }
      final activeSlidingSystem = profileSystemForSeries(
        widget.model.availableSystems,
        widget.model.activeSlidingSeries,
      );
      if (widget.model.activeSlidingSeries != null &&
          activeSlidingSystem != null &&
          _seriesMatchesScope(
            widget.model.activeSlidingSeries!,
            activeSlidingSystem,
            'sliding',
          ) &&
          widget.model.activeSlidingSeries!.id != primarySeries?.id &&
          !list.any((s) => s.id == widget.model.activeSlidingSeries!.id)) {
        list.add(widget.model.activeSlidingSeries!);
      }
      if (list.isEmpty || isInitialOrEmptyDrawing) {
        for (var system in widget.model.availableSystems) {
          for (var s in _seriesForScope(system, 'sliding')) {
            if (s.id != primarySeries?.id &&
                !list.any((existing) => existing.id == s.id)) {
              list.add(s);
            }
          }
        }
      }

      final uniqueList = <AluminumSeries>[];
      for (final s in list) {
        if (!uniqueList.any((existing) => existing.id == s.id)) {
          uniqueList.add(s);
        }
      }
      return uniqueList;
    }();

    final selectedSlidingValue =
        (widget.model.activeSlidingSeries != null &&
            slidingItemsList.any(
              (s) => s.id == widget.model.activeSlidingSeries!.id,
            ))
        ? slidingItemsList.firstWhere(
            (s) => s.id == widget.model.activeSlidingSeries!.id,
          )
        : null;
    // During the asynchronous catalogue switch, the model can briefly have
    // no sliding selection even though the selected opening system already
    // exposes valid sliding series. Show the actual first series immediately
    // and persist it, instead of showing the generic "Gamme المنزلق" hint.
    // A saved drawing can briefly have no resolved in-memory series while its
    // catalogue is still loading. Do not persist the first dropdown item in
    // that interval: doing so overwrote the saved BS90 id/name and reopened
    // every edited window with the default sliding series.
    final savedSlidingMatches = slidingItemsList.where(
      (series) =>
          series.id == widget.model.loadedSlidingSeriesId ||
          (widget.model.loadedSlidingSeriesName?.trim().isNotEmpty == true &&
              series.name.trim() ==
                  widget.model.loadedSlidingSeriesName!.trim()),
    );
    final hasPendingSavedSlidingSeries =
        widget.model.loadedSlidingSeriesId != null ||
        (widget.model.loadedSlidingSeriesName?.trim().isNotEmpty ?? false);
    final autoSlidingValue =
        selectedSlidingValue ??
        (savedSlidingMatches.isNotEmpty ? savedSlidingMatches.first : null) ??
        (!hasPendingSavedSlidingSeries &&
                isMixedDrawing &&
                slidingItemsList.isNotEmpty
            ? slidingItemsList.first
            : null);
    if (selectedSlidingValue == null &&
        isMixedDrawing &&
        autoSlidingValue != null) {
      _queueMixedSlidingSeriesSelection(
        autoSlidingValue,
        widget.model.activeSeries?.id,
      );
    }
    final safeSlidingValue = autoSlidingValue;

    return AppBar(
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      foregroundColor: isDark ? Colors.white : Colors.black,
      elevation: 0.5,
      titleSpacing: 8,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Row(
          children: [
            if (isShutterContext && shutterColorItems.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 170),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.shade900.withValues(alpha: 0.3)
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.orange.shade800
                        : Colors.orange.shade200,
                  ),
                ),
                child: DropdownButton<Map<String, dynamic>>(
                  isExpanded: true,
                  value: selectedShutterColor,
                  dropdownColor: isDark
                      ? const Color(0xFF1E1E2C)
                      : Colors.white,
                  hint: Text(
                    Localization.translate('لون الستار', lang),
                    style: TextStyle(
                      color: isDark
                          ? Colors.orange.shade300
                          : Colors.orange.shade800,
                      fontSize: 12,
                    ),
                  ),
                  underline: const SizedBox(),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: isDark
                        ? Colors.orange.shade300
                        : Colors.orange.shade800,
                    size: 18,
                  ),
                  items: shutterColorItems.map((colorData) {
                    final colorName =
                        (colorData['name'] ?? colorData['color_name'] ?? '')
                            .toString();
                    final parsedColor = getEffectiveGradientColors(
                      FrameColor.white,
                      colorData,
                    )[1];
                    final woodImage = _getWoodTextureImage(colorData);
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: colorData,
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: woodImage != null ? null : parsedColor,
                              image: woodImage,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              colorName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade800,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (newColor) {
                    if (newColor == null) return;
                    widget.model.selectedShutterColor =
                        Map<String, dynamic>.from(newColor);
                    unawaited(widget.model.updateShutterDefaultsIfNeeded());
                    widget.model.refreshUI();
                  },
                ),
              ),
            ],
            // A full window remains a full design even when the tunnel box or
            // shutter is selected. Keep its profile selectors visible; only
            // a truly standalone shutter hides the window-system controls.
            if (!isStandaloneShutterContext &&
                widget.model.availableSystems.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 160),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                decoration: BoxDecoration(
                  color: isDark
                      ? (selectorShowsSliding
                            ? Colors.green.shade900.withValues(alpha: 0.3)
                            : Colors.blue.shade900.withValues(alpha: 0.3))
                      : (selectorShowsSliding
                            ? Colors.green.shade50
                            : Colors.blue.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? (selectorShowsSliding
                              ? Colors.green.shade800
                              : Colors.blue.shade800)
                        : (selectorShowsSliding
                              ? Colors.green.shade200
                              : Colors.blue.shade200),
                  ),
                ),
                child: DropdownButton<AluminumSeries>(
                  isExpanded: true,
                  value: safePrimaryValue,
                  dropdownColor: isDark
                      ? const Color(0xFF1E1E2C)
                      : Colors.white,
                  hint: Text(
                    Localization.translate(
                      selectorShowsSliding ? 'سلسلة المنزلق' : 'سلسلة الفتح',
                      lang,
                    ),
                    style: TextStyle(
                      color: isDark
                          ? (selectorShowsSliding
                                ? Colors.green.shade300
                                : Colors.blue.shade300)
                          : (selectorShowsSliding ? Colors.green : Colors.blue),
                      fontSize: 12,
                    ),
                  ),
                  underline: const SizedBox(),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: isDark
                        ? (selectorShowsSliding
                              ? Colors.green.shade300
                              : Colors.blue.shade300)
                        : (selectorShowsSliding ? Colors.green : Colors.blue),
                    size: 18,
                  ),
                  items: primaryItemsList.map((series) {
                    return DropdownMenuItem<AluminumSeries>(
                      value: series,
                      child: Text(
                        series.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? (selectorShowsSliding
                                    ? Colors.green.shade300
                                    : Colors.blue.shade300)
                              : (selectorShowsSliding
                                    ? Colors.green
                                    : Colors.blue),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.visible,
                      ),
                    );
                  }).toList(),
                  onChanged: (AluminumSeries? newSeries) {
                    if (newSeries != null) {
                      if (isMixedDrawing || widget.model.systemMode == 'mixed') {
                        widget.model.systemMode = 'mixed';
                      } else if (isInitialOrEmptyDrawing &&
                          widget.systemMode != 'mixed') {
                        widget.model.systemMode = 'french';
                      }
                      if (selectorShowsSliding) {
                        unawaited(
                          widget.model.setActiveSlidingSeries(newSeries),
                        );
                      } else {
                        unawaited(widget.model.setActiveSeries(newSeries));
                      }
                    }
                  },
                ),
              ),
              // Show the sliding series selector when the drawing is mixed,
              // when the mode is mixed, or in initial/empty state so the user
              // can choose either or both from the start.
              if ((isMixedDrawing ||
                      isInitialOrEmptyDrawing ||
                      widget.model.systemMode == 'mixed' ||
                      widget.systemMode == 'mixed') &&
                  slidingItemsList.isNotEmpty) ...[
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
                    hint: Text(
                      Localization.translate('سلسلة المنزلق', lang),
                      style: TextStyle(
                        color: isDark ? Colors.green.shade300 : Colors.green,
                        fontSize: 12,
                      ),
                    ),
                    dropdownColor: isDark
                        ? const Color(0xFF1E1E2C)
                        : Colors.white,
                    underline: const SizedBox(),
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: isDark ? Colors.green.shade300 : Colors.green,
                      size: 18,
                    ),
                    items: slidingItemsList.map((series) {
                      return DropdownMenuItem<AluminumSeries>(
                        value: series,
                        child: Text(
                          series.name,
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
                        if (isInitialOrEmptyDrawing) {
                          widget.model.systemMode = 'sliding';
                        }
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
              onPressed: widget.model.canUndo
                  ? () {
                      widget.model.undo();
                      if (_isShutterSelected &&
                          !widget.model.isShutterOnly &&
                          (widget.model.zones.isNotEmpty ||
                              !widget.model.hasShutter)) {
                        setState(() {
                          _isShutterSelected = false;
                        });
                      }
                    }
                  : null,
              icon: const Icon(Icons.undo_rounded),
              tooltip: Localization.translate('تراجع', lang),
              color: widget.model.canUndo ? Colors.black87 : Colors.black26,
            ),

            // 🟢 زر الإعادة (Redo)
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              onPressed: widget.model.canRedo
                  ? () {
                      widget.model.redo();
                      if (widget.model.isShutterOnly && !_isShutterSelected) {
                        setState(() {
                          _isShutterSelected = true;
                        });
                      }
                    }
                  : null,
              icon: const Icon(Icons.redo_rounded),
              tooltip: Localization.translate('إعادة', lang),
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
                  ? Localization.translate(
                      'نسخ قياس الإطار السابق: مفعّل',
                      lang,
                    )
                  : Localization.translate('نسخ قياس الإطار السابق', lang),
              onPressed: widget.model.toggleCopyPreviousFrameSize,
            ),

            // 🟢 زر مسح الرسم بالكامل
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
              tooltip: Localization.translate('مسح الرسم', lang),
              onPressed: () => _showClearAllDialog(context),
            ),
          ],
        ),
      ),
      actions: [
        // The mobile bottom panel already owns the quantity/cost action.
        // Keeping this large AppBar action on a narrow screen squeezed the
        // drawing controls and produced horizontal overflow.
        if (_isWindowsDesktop)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 14, start: 6),
            child: Center(
              child: Tooltip(
                message: Localization.translate(
                  'فتح جدول الكمية والتكلفة',
                  lang,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? const [Color(0xFF047857), Color(0xFF065F46)]
                          : const [Color(0xFF10B981), Color(0xFF047857)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.16 : 0.3,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF065F46).withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _openMaterialConsumptionScreen(context),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          11,
                          7,
                          13,
                          7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 25,
                              height: 25,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              Localization.translate('الكمية والتكلفة', lang),
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSplitToolbar(BuildContext context, bool hasSelection) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                  'Dim: ${widget.model.width.toInt()} * ${widget.model.height.toInt()}',
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
            InkWell(
              onTap: _activateShutterFromDesign,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.model.hasShutter
                      ? Colors.orange.shade600
                      : Colors.blueGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.model.hasShutter
                          ? Icons.layers_rounded
                          : Icons.add_box_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      Localization.translate('ستار', lang),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              _tr('مسح الرسم'),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
        content: Text(
          _tr('هل أنت متأكد أنك تريد مسح الرسم بالكامل والبدء من جديد؟'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _tr('إلغاء'),
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              widget.model.clearAll();
              Navigator.pop(context);
            },
            child: Text(
              _tr('نعم، امسح'),
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

  void _showProfileAngleDialog(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final junctions = widget.model.getAdjacentFrameJunctions();
    final hasJunctions = junctions.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.square_foot_rounded,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Localization.translate(
                                  "بروفيل الزاوية 90° (Profil d'angle / Tube carré)",
                                  lang,
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (hasJunctions) ...[
                        Text(
                          Localization.translate(
                            'حدد الفواصل بين الإطارات المتلاصقة التي يركب فيها أنبوب الزاوية 90°:',
                            lang,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(Icons.select_all, size: 18),
                              label: Text(
                                Localization.translate('تحديد الكل', lang),
                              ),
                              onPressed: () {
                                widget.model.setAllProfileAngleJunctions(true);
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: Text(
                                Localization.translate('إلغاء الكل', lang),
                              ),
                              onPressed: () {
                                widget.model.setAllProfileAngleJunctions(false);
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...junctions.map((j) {
                          final isSelected = widget
                              .model
                              .activeProfileAngleJunctions
                              .contains(j.index);
                          return Card(
                            elevation: isSelected ? 2 : 0,
                            color: isSelected
                                ? Colors.blue.withOpacity(0.08)
                                : Theme.of(context).cardColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: CheckboxListTile(
                              title: Text(
                                j.localizedLabel(lang),
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.blue.shade900
                                      : null,
                                ),
                              ),
                              subtitle: Text(
                                Localization.translate(
                                  'طول القطاع: ${j.height.toStringAsFixed(0)} مم',
                                  lang,
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                              value: isSelected,
                              activeColor: Colors.blue,
                              onChanged: (checked) {
                                widget.model.toggleProfileAngleJunction(
                                  j.index,
                                  checked,
                                );
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color:
                                  widget
                                      .model
                                      .activeProfileAngleJunctions
                                      .isEmpty
                                  ? Colors.red.shade300
                                  : Colors.grey.shade300,
                            ),
                          ),
                          tileColor:
                              widget.model.activeProfileAngleJunctions.isEmpty
                              ? Colors.red.withOpacity(0.06)
                              : null,
                          leading: const Icon(
                            Icons.block_rounded,
                            color: Colors.red,
                          ),
                          title: Text(
                            Localization.translate(
                              'إلغاء بروفيل الزاوية بين الإطارات (إيقاف)',
                              lang,
                            ),
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            Localization.translate(
                              'بدون أي أنبوب زاوية بين الإطارات المتلاصقة',
                              lang,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing:
                              widget.model.activeProfileAngleJunctions.isEmpty
                              ? const Icon(Icons.check, color: Colors.red)
                              : null,
                          onTap: () {
                            widget.model.setAllProfileAngleJunctions(false);
                            setModalState(() {});
                            setState(() {});
                          },
                        ),
                        const Divider(height: 24),
                      ],
                      Text(
                        Localization.translate(
                          hasJunctions
                              ? 'أطراف الإطار الخارجية (يمين / يسار):'
                              : 'اختر جهة تركيب بروفيل الزاوية 90°:',
                          lang,
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ListTile(
                        leading: const Icon(
                          Icons.block_rounded,
                          color: Colors.grey,
                        ),
                        title: Text(
                          Localization.translate(
                            hasJunctions
                                ? 'بدون زاوية على الأطراف الخارجية'
                                : 'إيقاف / بدون بروفيل زاوية',
                            lang,
                          ),
                        ),
                        trailing: widget.model.profileAngleMode == 0
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          widget.model.setProfileAngleMode(0);
                          setModalState(() {});
                          setState(() {});
                          if (!hasJunctions) Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.border_right_rounded,
                          color: Colors.blue,
                        ),
                        title: Text(
                          Localization.translate(
                            'جهة اليمين (90° Droite)',
                            lang,
                          ),
                        ),
                        subtitle: Text(
                          Localization.translate(
                            'أنبوب زاوية 90° على القائم الأيمن الخارجي',
                            lang,
                          ),
                        ),
                        trailing: widget.model.profileAngleMode == 1
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          widget.model.setProfileAngleMode(1);
                          setModalState(() {});
                          setState(() {});
                          if (!hasJunctions) Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.border_left_rounded,
                          color: Colors.blue,
                        ),
                        title: Text(
                          Localization.translate(
                            'جهة اليسار (90° Gauche)',
                            lang,
                          ),
                        ),
                        subtitle: Text(
                          Localization.translate(
                            'أنبوب زاوية 90° على القائم الأيسر الخارجي',
                            lang,
                          ),
                        ),
                        trailing: widget.model.profileAngleMode == 2
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          widget.model.setProfileAngleMode(2);
                          setModalState(() {});
                          setState(() {});
                          if (!hasJunctions) Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.border_vertical_rounded,
                          color: Colors.blue,
                        ),
                        title: Text(
                          Localization.translate(
                            'الجهتين معاً (90° Les deux côtés)',
                            lang,
                          ),
                        ),
                        subtitle: Text(
                          Localization.translate(
                            'أنبوب زاوية 90° على القائمين الخارجيين',
                            lang,
                          ),
                        ),
                        trailing: widget.model.profileAngleMode == 3
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          widget.model.setProfileAngleMode(3);
                          setModalState(() {});
                          setState(() {});
                          if (!hasJunctions) Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSplitDialog(BuildContext context, bool isHorizontal) {
    final zone = widget.model.selectedZone;
    if (zone == null) return;
    final isSashTarget =
        zone.content == ZoneContent.singleSash ||
        zone.content == ZoneContent.doubleSash;
    final selectedRight =
        zone.content == ZoneContent.doubleSash &&
        widget.model.activeSubZone?.startsWith('right') == true;
    Rect measurementRect = zone.boundary;
    if (zone.content == ZoneContent.doubleSash) {
      final splitX =
          zone.boundary.left + zone.boundary.width * zone.doubleSashRatio;
      measurementRect = selectedRight
          ? Rect.fromLTRB(
              splitX + 2,
              zone.boundary.top,
              zone.boundary.right,
              zone.boundary.bottom,
            )
          : Rect.fromLTRB(
              zone.boundary.left,
              zone.boundary.top,
              splitX - 2,
              zone.boundary.bottom,
            );
    }
    if (isSashTarget) {
      measurementRect = widget.model.getSafeGlassRect(
        measurementRect,
        zone.sashThickness ?? widget.model.profileThickness,
      );
    }
    final double totalNetSize = isHorizontal
        ? measurementRect.height
        : measurementRect.width;
    final sashCount = widget.model.zones.fold<int>(0, (sum, candidate) {
      return sum +
          (candidate.content == ZoneContent.doubleSash
              ? 2
              : candidate.content == ZoneContent.singleSash
              ? 1
              : 0);
    });
    int parts = 2;
    bool isEqualSplit = true;
    bool fromStart = true;
    bool applyToAllSashes = false;
    TextEditingController part1Ctrl = TextEditingController();
    TextEditingController part2Ctrl = TextEditingController();

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark ? Colors.white70 : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final dropdownBgColor = isDark ? const Color(0xFF2D2D3F) : Colors.white;

    String getRemainingText() {
      if (parts == 2) {
        double p1 = double.tryParse(part1Ctrl.text) ?? 0;
        return '${Localization.translate('المتبقي', lang)}: ${(totalNetSize - p1).toStringAsFixed(1)} mm';
      } else if (parts == 3) {
        double p1 = double.tryParse(part1Ctrl.text) ?? 0;
        double p2 = double.tryParse(part2Ctrl.text) ?? 0;
        return '${Localization.translate('القطعة الوسطى', lang)}: ${(totalNetSize - p1 - p2).toStringAsFixed(1)} mm';
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
                      onChanged: (v) => setState(() {
                        isEqualSplit = v!;
                        part1Ctrl.clear();
                        part2Ctrl.clear();
                      }),
                      activeColor: Colors.blue,
                    ),
                    Divider(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                    ),
                    if (isSashTarget && sashCount > 1) ...[
                      RadioListTile<bool>(
                        title: Text(
                          Localization.translate(
                            'تطبيق على الضلفة المحددة فقط',
                            lang,
                          ),
                          style: TextStyle(color: textColor),
                        ),
                        value: false,
                        groupValue: applyToAllSashes,
                        onChanged: (value) =>
                            setState(() => applyToAllSashes = value ?? false),
                        activeColor: Colors.blue,
                      ),
                      RadioListTile<bool>(
                        title: Text(
                          Localization.translate(
                            'تطبيق نفس التقسيم على كل الضلفات',
                            lang,
                          ),
                          style: TextStyle(color: textColor),
                        ),
                        value: true,
                        groupValue: applyToAllSashes,
                        onChanged: (value) =>
                            setState(() => applyToAllSashes = value ?? true),
                        activeColor: Colors.blue,
                      ),
                      Divider(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                      ),
                    ],
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
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      '$e ${Localization.translate('قطع', lang)}',
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
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          '$e ${Localization.translate('قطع', lang)}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  parts = v!;
                                  part1Ctrl.clear();
                                  part2Ctrl.clear();
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${Localization.translate('إجمالي القياس الصافي', lang)}: ${totalNetSize.toStringAsFixed(1)} mm',
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
                          ] else if (parts == 3) ...[
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
                    List<double>? customSizes;
                    if (!isEqualSplit) {
                      if (parts == 2) {
                        customSizes = [
                          double.tryParse(part1Ctrl.text) ?? (totalNetSize / 2),
                        ];
                      } else if (parts == 3) {
                        customSizes = [
                          double.tryParse(part1Ctrl.text) ?? (totalNetSize / 3),
                          double.tryParse(part2Ctrl.text) ?? (totalNetSize / 3),
                        ];
                      }
                    }
                    if (isSashTarget) {
                      widget.model.configureSelectedSashDivisions(
                        horizontal: isHorizontal,
                        parts: parts,
                        customSizes: customSizes,
                        fromStart: fromStart,
                        applyToAllSashes: applyToAllSashes,
                      );
                      Navigator.pop(context);
                      return;
                    }
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String seriesName = activeSeriesForSystem != null
        ? activeSeriesForSystem!.name.toLowerCase()
        : '';
    final effSliding = widget.model.effectiveSlidingSeries ??
        widget.model.activeSlidingSeries;
    String slidingSeriesName = effSliding != null
        ? effSliding.name.toLowerCase()
        : seriesName;
    final useSlidingFrame =
        widget.model.usesSlidingPrimaryProfiles ||
        zone.content == ZoneContent.slidingSash ||
        widget.systemMode == 'sliding';
    final selectedFrame = useSlidingFrame
        ? widget.model.getSlidingBaseFrameSection()?.toMap()
        : widget.model.frameOverride;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.40,
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
                    label: selectedFrame != null
                        ? '${selectedFrame['name']}'
                        : Localization.translate('اختر الإطار (Cadre)', lang),
                    icon: Icons.border_outer_rounded,
                    selected: selectedFrame != null,
                    onPressed: () async {
                      final useSlidingProfiles = useSlidingFrame;
                      final selected = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) => ProfileSelectorDialog(
                          profileType: 'Frame',
                          seriesId: useSlidingProfiles
                              ? (widget.model.effectiveSlidingSeries?.id ??
                                  widget.model.activeSlidingSeries?.id)
                              : widget.model.activeSeries?.id,
                          materialType: useSlidingProfiles
                              ? (widget.model.isSlidingPVC
                                    ? 'PVC'
                                    : 'Aluminium')
                              : (widget.model.isPVC ? 'PVC' : 'Aluminium'),
                          hasShutter: widget.model.hasShutter,
                          isCaissonTunnel: widget.model.isCaissonTunnel,
                          hasSideCovers: widget.model.hasSideCovers,
                          multiFrameDrawing:
                              widget.model.getFrameRects().length > 1,
                          accessoryDrawingMode: useSlidingProfiles
                              ? AccessoryDrawingMode.sliding
                              : AccessoryDrawingMode.opening,
                          hasSimpleGlassForReducer:
                              widget.model.hasSimpleGlassForReducer,
                          hasDoubleGlassForRules:
                              widget.model.hasDoubleGlassForRules,
                        ),
                      );
                      if (selected != null) {
                        final mutableSelected = Map<String, dynamic>.from(
                          selected,
                        );
                        mutableSelected['calculated_price'] =
                            await _sectionPriceForSelectedColor(
                              mutableSelected,
                            );

                        setState(() {
                          widget.model.applyFrameOverride(
                            mutableSelected,
                            sliding: useSlidingProfiles,
                            manualSelection: true,
                          );
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
                      label:
                          ((zone.content == ZoneContent.slidingSash ||
                                      widget.systemMode == 'sliding')
                                  ? widget.model.slidingSashOverride
                                  : widget.model.sashOverride) !=
                              null
                          ? '${((zone.content == ZoneContent.slidingSash || widget.systemMode == 'sliding') ? widget.model.slidingSashOverride : widget.model.sashOverride)!['name']}'
                          : Localization.translate('اختر الظلفة (Sash)', lang),
                      icon: Icons.format_paint_rounded,
                      selected:
                          ((zone.content == ZoneContent.slidingSash ||
                                  widget.systemMode == 'sliding')
                              ? widget.model.slidingSashOverride
                              : widget.model.sashOverride) !=
                          null,
                      onPressed: () async {
                        final useSlidingProfiles =
                            zone.content == ZoneContent.slidingSash ||
                            widget.systemMode == 'sliding';
                        final selected = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (context) => ProfileSelectorDialog(
                            profileType: 'sash',
                            seriesId: useSlidingProfiles
                                ? (widget.model.effectiveSlidingSeries?.id ??
                                    widget.model.activeSlidingSeries?.id)
                                : widget.model.activeSeries?.id,
                            materialType: useSlidingProfiles
                                ? (widget.model.isSlidingPVC
                                      ? 'PVC'
                                      : 'Aluminium')
                                : (widget.model.isPVC ? 'PVC' : 'Aluminium'),
                            accessoryDrawingMode: useSlidingProfiles
                                ? AccessoryDrawingMode.sliding
                                : AccessoryDrawingMode.opening,
                            hasSimpleGlassForReducer:
                                widget.model.hasSimpleGlassForReducer,
                            hasDoubleGlassForRules:
                                widget.model.hasDoubleGlassForRules,
                          ),
                        );
                        if (selected != null) {
                          final mutableSelected = Map<String, dynamic>.from(
                            selected,
                          );
                          mutableSelected['calculated_price'] =
                              await _sectionPriceForSelectedColor(
                                mutableSelected,
                              );

                          setState(() {
                            widget.model.applySashOverride(
                              mutableSelected,
                              sliding: useSlidingProfiles,
                              manualSelection: true,
                            );
                            widget.model.refreshUI();
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
                      if (zone.slidingSashesCount >= 4 &&
                          zone.slidingSashesCount % 2 == 0) ...[
                        if (widget.model.supportsSlidingFaceToFace) ...[
                          const SizedBox(width: 8),
                          _ContentButton(
                            label: Localization.translate(
                              'التقاء الوسط (Face-to-Face)',
                              lang,
                            ),
                            icon: Icons.layers_rounded,
                            selected: zone.slidingFaceToFace,
                            onPressed: () {
                              setState(() {
                                widget.model
                                    .toggleSelectedZoneSlidingFaceToFace();
                              });
                            },
                          ),
                        ],
                        if (zone.slidingFaceToFace ||
                            (zone.slidingSashesCount == 6 &&
                                zone.slidingTrackCount == 3)) ...[
                          const SizedBox(width: 8),
                          _ContentButton(
                            label: 'مقبض وسط الضلفتين',
                            icon: Icons.more_horiz_rounded,
                            selected: zone.slidingCentralHandle,
                            onPressed: () {
                              setState(() {
                                widget.model
                                    .toggleSelectedZoneSlidingCentralHandle();
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _ContentButton(
                            label: 'مقبض الوسط الثاني (شكلي)',
                            icon: Icons.more_horiz_outlined,
                            selected: zone.slidingSecondCentralHandle,
                            onPressed: () {
                              if (!zone.slidingCentralHandle) return;
                              setState(() {
                                widget.model
                                    .toggleSelectedZoneSlidingSecondCentralHandle();
                              });
                            },
                          ),
                        ],
                      ],
                    ],
                    const SizedBox(width: 8),
                    ...(zone.content == ZoneContent.doubleSash ||
                                zone.content == ZoneContent.slidingSash
                            ? [OpenDirection.left, OpenDirection.right]
                            : OpenDirection.values)
                        .map(
                          (dir) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _ContentButton(
                              label: _getDirectionName(dir),
                              icon: Icons.open_with_rounded,
                              selected: zone.openDirection == dir,
                              onPressed: () => widget.model
                                  .setSelectedZoneOpenDirection(dir),
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _tr('نوع المنطقة:'),
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
                        label: _slidingCountLabel(2, lang),
                        icon: Icons.sync_alt_rounded,
                        selected:
                            zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 2,
                        onPressed: () async {
                          if (widget.model.hasArchOrSlant) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _tr(
                                    'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                  ),
                                  textDirection: TextDirection.rtl,
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            await _setSelectedZoneSlidingSashesFromUi(2);
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
                          label: _slidingCountLabel(3, lang),
                          icon: Icons.sync_alt_rounded,
                          selected:
                              zone.content == ZoneContent.slidingSash &&
                              zone.slidingSashesCount == 3,
                          onPressed: () async {
                            if (widget.model.hasArchOrSlant) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _tr(
                                      'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                    ),
                                    textDirection: TextDirection.rtl,
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } else {
                              await _setSelectedZoneSlidingSashesFromUi(3);
                            }
                          },
                        ),
                      ],
                      if (slidingSeriesName.contains('h36') ||
                          slidingSeriesName.contains('hps')) ...[
                        const SizedBox(width: 8),
                        _ContentButton(
                          label: _slidingCountLabel(4, lang),
                          icon: Icons.sync_alt_rounded,
                          selected:
                              zone.content == ZoneContent.slidingSash &&
                              zone.slidingSashesCount == 4,
                          onPressed: () async {
                            if (widget.model.hasArchOrSlant) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _tr(
                                      'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                    ),
                                    textDirection: TextDirection.rtl,
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } else {
                              await _setSelectedZoneSlidingSashesFromUi(4);
                            }
                          },
                        ),
                      ],
                    ],
                  ],
                  if (widget.systemMode == 'sliding' && isSlidingSupported) ...[
                    _ContentButton(
                      label: _slidingCountLabel(2, lang),
                      icon: Icons.sync_alt_rounded,
                      selected:
                          zone.content == ZoneContent.slidingSash &&
                          zone.slidingSashesCount == 2,
                      onPressed: () async {
                        if (widget.model.hasArchOrSlant) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _tr(
                                  'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } else {
                          await _setSelectedZoneSlidingSashesFromUi(2);
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
                        label: _slidingCountLabel(3, lang),
                        icon: Icons.sync_alt_rounded,
                        selected:
                            zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 3,
                        onPressed: () async {
                          if (widget.model.hasArchOrSlant) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _tr(
                                    'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                  ),
                                  textDirection: TextDirection.rtl,
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            await _setSelectedZoneSlidingSashesFromUi(3);
                          }
                        },
                      ),
                    ],
                    if (slidingSeriesName.contains('h36') ||
                        slidingSeriesName.contains('hps')) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: _slidingCountLabel(4, lang),
                        icon: Icons.sync_alt_rounded,
                        selected:
                            zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 4,
                        onPressed: () async {
                          if (widget.model.hasArchOrSlant) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _tr(
                                    'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                                  ),
                                  textDirection: TextDirection.rtl,
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else {
                            await _setSelectedZoneSlidingSashesFromUi(4);
                          }
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
            if (zone.content == ZoneContent.slidingSash) ...[
              const SizedBox(height: 12),
              Text(
                _trackTitle(context.read<AppSettingsProvider>().language),
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
                  children: [2, 3, 4, 5]
                      .map(
                        (count) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ContentButton(
                            label: _trackCountLabel(
                              count,
                              context.read<AppSettingsProvider>().language,
                            ),
                            icon: Icons.view_week_rounded,
                            selected: zone.slidingTrackCount == count,
                            onPressed: () => widget.model
                                .setSelectedZoneSlidingTracks(count),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _frameTrackCompositionLabel(
                  zone.slidingTrackCount,
                  widget.model.selectedSlidingFrameIsComplete,
                  context.read<AppSettingsProvider>().language,
                ),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
              ),
            ],
            if (widget.model.activeSubZone != null &&
                (widget.model.activeSubZone!.contains('cell_') ||
                    zone.content == ZoneContent.fixedGlass)) ...[
              const SizedBox(height: 12),
              Text(
                _tr('مظهر القسم المحدد:'),
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
                                      (dir) => Padding(
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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

  String _getClosedColoreName(ClosedGlassColor d) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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

  int? _selectedProfileColorId() {
    final rawId = widget.model.selectedDbColor?['id'];
    return rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
  }

  int? _catalogRowId(Map<String, dynamic> item) {
    final rawId = item['id'];
    return rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
  }

  Future<double> _sectionPriceForSelectedColor(
    Map<String, dynamic> item,
  ) async {
    final sectionId = _catalogRowId(item);
    final colorId = _selectedProfileColorId();
    if (sectionId == null || colorId == null) return 0.0;
    try {
      return await SqlDatabase().getSectionPrice(sectionId, colorId);
    } catch (error) {
      debugPrint('Failed to resolve section price for drawing button: $error');
      return 0.0;
    }
  }

  bool _isReinforcedMontant(
    Map<String, dynamic> item, {
    required bool central,
  }) {
    return widget.model.isSlidingMontantReinforced(item, central: central);
  }

  bool _isSlidingMontantCandidate(
    Map<String, dynamic> item, {
    required bool central,
  }) {
    if (widget.model.isSlidingMontantSlimCandidate(item)) {
      return false;
    }
    final role = (item['design_role_key'] ?? '').toString();
    if (role.isNotEmpty) {
      return central
          ? const [
              'sash_central',
              'sash_central_reinforced',
              'central',
              'chicane',
              'chicane_renforcee',
            ].contains(role)
          : const [
              'sash_lateral',
              'sash_lateral_reinforced',
              'lateral',
            ].contains(role);
    }
    final name = (item['name'] ?? '').toString().toLowerCase();
    final type = (item['type'] ?? '').toString().toLowerCase();
    final isOpeningSash =
        type.contains('ouvrant') ||
        type.contains('opening') ||
        name.contains('ouvrant') ||
        name.contains('opening');
    if (isOpeningSash &&
        !type.contains('sliding') &&
        !name.contains('coulissant') &&
        !name.contains('منزلق')) {
      return false;
    }
    final id = _catalogRowId(item);
    if (id != null) {
      final inCentralRole = _slidingCentralProfileIds.contains(id);
      final inLateralRole = _slidingLateralProfileIds.contains(id);
      if (central && inCentralRole) return true;
      if (!central && inLateralRole) return true;
      if (central && inLateralRole) return false;
      if (!central && inCentralRole) return false;
    }

    final code = (item['code'] ?? '').toString().trim().toLowerCase();
    if (central) {
      return type.contains('central') ||
          type.contains('وسطي') ||
          name.contains('central') ||
          name.contains('وسطي') ||
          type.contains('chicane') ||
          name.contains('chicane') ||
          type.contains('شيكان') ||
          name.contains('شيكان') ||
          code.endsWith('105') ||
          code.endsWith('107');
    }
    return type.contains('lateral') ||
        type.contains('latéral') ||
        type.contains('جانبي') ||
        name.contains('lateral') ||
        name.contains('latéral') ||
        name.contains('جانبي') ||
        code.endsWith('104') ||
        code.endsWith('108');
  }

  Future<void> _syncSlidingMontantOverrideFromFlags({
    required bool central,
  }) async {
    if (_pvcMontantReinforcementDisabled) return;

    final hasReinforced = central
        ? widget.model.zones.any(
            (zone) => zone.slidingMontantReinforced.entries.any(
              (entry) => entry.key.startsWith('central_') && entry.value,
            ),
          )
        : widget.model.zones.any(
            (zone) =>
                zone.slidingMontantReinforced['lateral_0'] == true ||
                zone.slidingMontantReinforced['lateral_1'] == true,
          );

    final hasNormal = central
        ? widget.model.zones.any((zone) {
            if (zone.content != ZoneContent.slidingSash) return false;
            final sashes = zone.slidingSashesCount > 0
                ? zone.slidingSashesCount
                : 2;
            final centralCount = math.max(0, (sashes * 2) - 2);
            for (var i = 0; i < centralCount; i++) {
              if (zone.slidingMontantReinforced['central_$i'] != true) {
                return true;
              }
            }
            return false;
          })
        : widget.model.zones.any(
            (zone) =>
                zone.content == ZoneContent.slidingSash &&
                (zone.slidingMontantReinforced['lateral_0'] != true ||
                    zone.slidingMontantReinforced['lateral_1'] != true),
          );

    final allCandidates =
        <Map<String, dynamic>>[
              ..._sashProfiles,
              ..._slidingSashProfiles,
              ...?(widget.model.effectiveSlidingSeries ??
                      widget.model.activeSlidingSeries)
                  ?.sections
                  .map((s) => s.toMap()),
            ]
            .where((item) => _isSlidingMontantCandidate(item, central: central))
            .toList();

    if (allCandidates.isEmpty) return;

    final reinforcedKey = central
        ? 'قائم وسطي معزز (Sash Central Renforcé)'
        : 'قائم جانبي معزز (Sash Lateral Renforcé)';
    final normalKey = central
        ? 'قائم وسطي (Sash Central)'
        : 'قائم جانبي (Sash Lateral)';

    if (hasReinforced) {
      if (!widget.model.componentOverrides.containsKey(reinforcedKey)) {
        var rCandidates = allCandidates
            .where((item) => _isReinforcedMontant(item, central: central))
            .toList();
        if (rCandidates.isEmpty && central) {
          final chicaneCandidates = allCandidates.where((item) {
            final t =
                '${item['type'] ?? ''} ${item['name'] ?? ''} ${item['design_role_key'] ?? ''}'
                    .toLowerCase();
            return t.contains('chicane') ||
                t.contains('شيكان') ||
                t.contains('renforc') ||
                t.contains('معزز');
          }).toList();
          if (chicaneCandidates.isNotEmpty) rCandidates = chicaneCandidates;
        }
        if (rCandidates.isNotEmpty) {
          final selected = Map<String, dynamic>.from(rCandidates.first);
          selected['calculated_price'] = await _sectionPriceForSelectedColor(
            selected,
          );
          widget.model.applySlidingMontantOverride(
            selected,
            central: central,
            reinforced: true,
            manualSelection: true,
            updateAllMembers: false,
          );
        }
      }
    } else {
      widget.model.componentOverrides.remove(reinforcedKey);
    }

    if (hasNormal) {
      final hasAnyNormalOverride =
          widget.model.componentOverrides.containsKey(normalKey) ||
          widget.model.componentOverrides.containsKey(
            central ? 'قائم وسطي (Central)' : 'قائم جانبي (Lateral)',
          );
      if (!hasAnyNormalOverride) {
        final nCandidates = allCandidates
            .where((item) => !_isReinforcedMontant(item, central: central))
            .toList();
        if (nCandidates.isNotEmpty) {
          final selected = Map<String, dynamic>.from(nCandidates.first);
          selected['calculated_price'] = await _sectionPriceForSelectedColor(
            selected,
          );
          widget.model.applySlidingMontantOverride(
            selected,
            central: central,
            reinforced: false,
            manualSelection: true,
            updateAllMembers: false,
          );
        }
      }
    } else {
      widget.model.componentOverrides.remove(normalKey);
      widget.model.componentOverrides.remove(
        central ? 'قائم وسطي (Central)' : 'قائم جانبي (Lateral)',
      );
    }

    if (!mounted) return;
    setState(() {
      widget.model.refreshUI();
    });
  }

  List<Widget> _arrangeInTwoRows(List<Widget> rawItems) {
    // Keep the action palette compact. A long single line hides options behind
    // a horizontal scrollbar, whereas two deterministic rows keep both the
    // opening and sliding controls immediately visible.
    final items = rawItems.where((w) => w is! SizedBox).toList();
    if (items.isEmpty) return [];
    if (items.length <= 5) {
      return [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: items
              .map((item) => item is _Tier2RowItem ? item.child : item)
              .toList(growable: false),
        ),
      ];
    }

    final firstRow = <Widget>[];
    final secondRow = <Widget>[];
    final firstRowCapacity = (items.length + 1) ~/ 2;
    for (final item in items) {
      if (item is _Tier2RowItem) {
        // Explicit groups (opening / sliding frame choices) retain their
        // own stable row even when optional controls appear or disappear.
        (item.rowIndex == 0 ? firstRow : secondRow).add(item.child);
      } else if (firstRow.length < firstRowCapacity) {
        firstRow.add(item);
      } else {
        secondRow.add(item);
      }
    }
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: firstRow),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: secondRow),
        ],
      ),
    ];
  }

  Widget _buildInteractiveBottomPanel(BuildContext context) {
    final hasSelection = widget.model.selectedZone != null;
    final isMullionSelected =
        widget.model.selection.type == SelectionType.mullion;

    // ── إذا تم تحديد الستار → اعرض لوحة الستار ──
    if ((widget.model.isShutterOnly && _isBottomPanelExpanded) ||
        (_isShutterSelected &&
            (widget.model.hasShutter ||
                widget.model.drawNextShapeAsShutterOnly))) {
      return _buildShutterBottomPanel(context);
    }

    // A drawing selection opens the panel automatically. The chevron remains
    // available to open it manually when nothing is selected.
    final showExpanded = _isBottomPanelExpanded;

    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    // Opening the panel is enough to work with the drawing:
                    // use the first frame as the active context so the frame,
                    // sash, glass and handle tabs are immediately available.
                    if (widget.model.selectedZone == null &&
                        widget.model.zones.isNotEmpty) {
                      widget.model.selection = SelectionInfo.zone(
                        widget.model.zones.first.id,
                      );
                      _activeBottomTab = 0;
                    }
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
                // Keep the two-row layout, but it must remain horizontally
                // draggable on phones when the available actions exceed the
                // narrow viewport instead of overflowing and freezing.
                Container(
                  height: 110,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: _HorizontalWheelScrollArea(
                    builder: (context, controller) => SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Row(
                          children: _arrangeInTwoRows(
                            _buildTier2Options(context, isMullionSelected),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else
                _buildZoneContentPaintPicker(context),
            ] else ...[
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            if (!widget.model.isShutterOnly) ...[
              // ── Main Tab Bar showing "الستار (Volet)" selected ──
              _buildTier1TabBar(isMullionSelected),
              const Divider(height: 1, thickness: 0.5),
            ],
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
                      builder: (context, controller) => SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          // Caissons, blades and tracks can have long labels.
                          // Keep every shutter option on one horizontally
                          // scrollable row instead of forcing two tall rows
                          // into the fixed bottom-panel height.
                          children: _buildShutterTier2Options(context),
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
        builder: (context, controller) => ListView.builder(
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

    if (!widget.model.isShutterOnly) {
      // تفعيل/إلغاء الستار
      items.add(
        _ShutterChip(
          label: 'الستار مفعّل',
          icon: Icons.layers_rounded,
          selected: widget.model.hasShutter,
          color: Colors.orange,
          onTap: () {
            final enable = !widget.model.hasShutter;
            setState(() {
              widget.model.toggleShutter(enable);
              if (!enable) _isShutterSelected = false;
            });
          },
        ),
      );
      items.add(const SizedBox(width: 8));
    }

    if (widget.model.hasShutter && widget.model.shutterWidthWarning != null) {
      final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
      final rec = widget.model.recommendedShutterBlade;
      items.add(
        Container(
          width: 360,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.straighten, color: Colors.orange.shade800, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.model.localizedShutterWidthWarning(lang) ??
                          widget.model.shutterWidthWarning!,
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (rec != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 14),
                    label: Text(
                      lang == AppLanguage.french
                          ? 'Appliquer la recommandation'
                          : (lang == AppLanguage.english
                              ? 'Apply recommendation'
                              : 'تطبيق المقترح'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      widget.model.applyRecommendedShutterBlade();
                      await widget.model.updateShutterDefaultsIfNeeded();
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      items.add(const SizedBox(width: 8));
    }

    if (widget.model.shutterHeightWarning != null) {
      items.add(
        _ShutterChip(
          label: widget.model.shutterHeightWarning!,
          icon: Icons.warning_amber_rounded,
          selected: true,
          color: Colors.red,
          onTap: () {},
        ),
      );
      items.add(const SizedBox(width: 8));
    }

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
        onTap: () async {
          await widget.model.toggleSideCovers(!widget.model.hasSideCovers);
          if (mounted) setState(() {});
        },
      ),
    );

    return items;
  }

  // تبويب الصندوق
  List<Widget> _buildShutterCaissonOptions(BuildContext context) {
    if (_shutterCaissonOptions.isEmpty) {
      return [
        Center(
          child: Text(
            _tr('لا توجد صناديق في قاعدة البيانات'),
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final current = widget.model.componentOverrides['الصندوق (Caisson)'];
    final currentId = current?['id'];
    return _shutterCaissonOptions.map((opt) {
      final optionId = (opt['id'] as num?)?.toInt();
      final isTunnelOption = _isCaissonTunnelOption(opt);
      final unavailableReason = optionId == null
          ? null
          : _unavailableCaissonReasons[optionId];
      final isAvailable = unavailableReason == null;
      final isSelected = isTunnelOption
          ? widget.model.isCaissonTunnel
          : (!widget.model.isCaissonTunnel &&
                currentId != null &&
                opt['id'] == currentId);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterChip(
            label: opt['name']?.toString() ?? '',
            icon: isAvailable ? Icons.inbox_rounded : Icons.block_outlined,
            selected: isSelected,
            color: Colors.indigo,
            enabled: isAvailable,
            disabledHint: unavailableReason,
            onTap: () async {
              if (isTunnelOption) {
                widget.model.toggleCaissonTunnel(true);
                if (mounted) setState(() {});
                return;
              }
              final mutable = Map<String, dynamic>.from(opt);
              final rawPrice = opt['price_dzd'] ?? opt['price'] ?? 0.0;
              mutable['calculated_price'] = rawPrice is num
                  ? rawPrice.toDouble()
                  : double.tryParse(rawPrice.toString()) ?? 0.0;
              mutable['manual_selection'] = true;
              // A normal caisson must always leave tunnel mode first; otherwise
              // `shutterBoxHeight` is locked to the tunnel height and the
              // drawing keeps showing the old large box.
              if (widget.model.isCaissonTunnel) {
                widget.model.toggleCaissonTunnel(false);
              }
              widget.model.componentOverrides['الصندوق (Caisson)'] = mutable;
              await widget.model.updateShutterDefaultsIfNeeded();
              if (mounted) setState(() {});
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
        Center(
          child: Text(
            _tr('لا توجد شفرات في قاعدة البيانات'),
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final lang =
        Provider.of<AppSettingsProvider>(context, listen: false).language;
    final current = widget.model.componentOverrides['الشرائح (Lames)'];
    final currentId = current?['id'];
    final list = _shutterLamesOptions.map<Widget>((opt) {
      final isSelected = currentId != null && opt['id'] == currentId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterChip(
            label: opt['name']?.toString() ?? '',
            icon: Icons.view_week_rounded,
            selected: isSelected,
            color: Colors.brown,
            onTap: () async {
              final mutable = Map<String, dynamic>.from(opt);
              // Selecting a blade from the drawer is an explicit user choice.
              // Keep it even when its configured width is below the window;
              // the model will show a warning instead of silently replacing it.
              mutable['manual_selection'] = true;
              mutable['user_selected'] = true;
              mutable['automatic_selection'] = false;
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
              await widget.model.updateShutterDefaultsIfNeeded();
              if (!mounted) return;
              final selected =
                  widget.model.componentOverrides['الشرائح (Lames)'];
              if (selected?['id'] != opt['id']) return;
              final warning = widget.model.localizedShutterWidthWarning(lang) ??
                  widget.model.shutterWidthWarning;
              if (warning != null) {
                final rec = widget.model.recommendedShutterBlade;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(warning),
                      backgroundColor: Colors.orange.shade900,
                      duration: const Duration(seconds: 8),
                      action: rec != null
                          ? SnackBarAction(
                              label: lang == AppLanguage.french
                                  ? 'Appliquer'
                                  : (lang == AppLanguage.english
                                      ? 'Apply'
                                      : 'تطبيق المقترح'),
                              textColor: Colors.yellowAccent,
                              onPressed: () async {
                                widget.model.applyRecommendedShutterBlade();
                                await widget.model.updateShutterDefaultsIfNeeded();
                                if (mounted) setState(() {});
                              },
                            )
                          : null,
                    ),
                  );
              }
              setState(() {});
            },
          ),
          const SizedBox(width: 8),
        ],
      );
    }).toList();

    if (widget.model.shutterWidthWarning != null) {
      final warning = widget.model.localizedShutterWidthWarning(lang) ??
          widget.model.shutterWidthWarning!;
      final rec = widget.model.recommendedShutterBlade;
      list.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.orange.shade900,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    warning,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (rec != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade900,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check_circle, size: 14),
                    label: Text(
                      lang == AppLanguage.french
                          ? 'Appliquer'
                          : (lang == AppLanguage.english ? 'Apply' : 'تطبيق'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      widget.model.applyRecommendedShutterBlade();
                      await widget.model.updateShutterDefaultsIfNeeded();
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return list;
  }

  // تبويب السكك
  List<Widget> _buildShutterCoulisseOptions(BuildContext context) {
    final selectedBlade = widget.model.componentOverrides['الشرائح (Lames)'];
    final requiredTrackMeasurement = selectedBlade == null
        ? null
        : WindowModel.shutterMeasurementKey(
            Map<String, dynamic>.from(selectedBlade),
            preferTrackMeasurement: true,
          );
    final compatibleOptions = selectedBlade == null
        ? _shutterCoulisseOptions
        : WindowModel.compatibleShutterTracks(
            Map<String, dynamic>.from(selectedBlade),
            _shutterCoulisseOptions,
          );
    final options = requiredTrackMeasurement == null
        ? _shutterCoulisseOptions
        : compatibleOptions;
    if (options.isEmpty) {
      return [
        Center(
          child: Text(
            requiredTrackMeasurement == null
                ? 'لا توجد سكك في قاعدة البيانات'
                : 'لا توجد سكة مرتبطة بقياس $requiredTrackMeasurement مم لهذه الشفرة',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final current = widget.model.componentOverrides['السكك (Coulisses)'];
    final currentId = current?['id'];
    return options.map((opt) {
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
              final rawPrice = opt['price_dzd'] ?? opt['price'] ?? 0.0;
              mutable['calculated_price'] = rawPrice is num
                  ? rawPrice.toDouble()
                  : double.tryParse(rawPrice.toString()) ?? 0.0;
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
        builder: (context, controller) => ListView.builder(
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
                    // Consume the existing drawing selection before async
                    // catalogue notifications arrive; it is not a new click
                    // on the canvas and must not close this explicit tab.
                    _previousSelectionKey = _currentSelectionKey();
                    _loadShutterOptions();
                  } else {
                    _isShutterSelected = false;
                    _activeBottomTab = id;
                    _handleCandidates = null;
                    if (id == 1) {
                      if (widget.model.selection.type != SelectionType.frame &&
                          widget.model.getFrameRects().isNotEmpty) {
                        widget.model.selectFrameByIndex(0);
                      }
                    } else if (widget.model.selectedZone == null &&
                        widget.model.zones.isNotEmpty) {
                      widget.model.selection = SelectionInfo.zone(
                        widget.model.zones.first.id,
                      );
                    }
                    // This selection was created by the bottom bar itself.
                    // Mark it consumed so the following model notification
                    // cannot reset the newly chosen tab.
                    _previousSelectionKey = _currentSelectionKey();
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
                          : (Theme.of(context).brightness == Brightness.dark
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
                            : (Theme.of(context).brightness == Brightness.dark
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

  List<Widget> _buildTier2Options(
    BuildContext context,
    bool isMullionSelected,
  ) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final zone = widget.model.selectedZone;
    if (zone == null) return [];

    final supportedSlidingCounts = widget.model.supportedSlidingSashCounts;
    final supportedTrackCounts = widget.model.supportedSlidingTrackCounts;

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
                onPressed: () async {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          Localization.translate(
                            _tr('نظام المنزلق لا يدعم الشكل المائل والمقوس'),
                            lang,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    await _setSelectedZoneSlidingSashesFromUi(2);
                  }
                },
              ),
            );

            if (supportedSlidingCounts.contains(3)) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: Localization.translate('منزلق 3', lang),
                  icon: Icons.sync_alt_rounded,
                  selected:
                      zone.content == ZoneContent.slidingSash &&
                      zone.slidingSashesCount == 3,
                  onPressed: () async {
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
                      await _setSelectedZoneSlidingSashesFromUi(3);
                    }
                  },
                ),
              );
            }

            if (supportedSlidingCounts.contains(4)) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: Localization.translate('منزلق 4', lang),
                  icon: Icons.sync_alt_rounded,
                  selected:
                      zone.content == ZoneContent.slidingSash &&
                      zone.slidingSashesCount == 4,
                  onPressed: () async {
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
                      await _setSelectedZoneSlidingSashesFromUi(4);
                    }
                  },
                ),
              );
            }
          }
        } else if (isSlidingSupported) {
          children.add(
            _ContentButton(
              label: _slidingCountLabel(2, lang),
              icon: Icons.sync_alt_rounded,
              selected:
                  zone.content == ZoneContent.slidingSash &&
                  zone.slidingSashesCount == 2,
              onPressed: () async {
                if (widget.model.hasArchOrSlant) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                        textDirection: TextDirection.rtl,
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else {
                  await _setSelectedZoneSlidingSashesFromUi(2);
                }
              },
            ),
          );

          if (supportedSlidingCounts.contains(3)) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: _slidingCountLabel(3, lang),
                icon: Icons.sync_alt_rounded,
                selected:
                    zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == 3,
                onPressed: () async {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    await _setSelectedZoneSlidingSashesFromUi(3);
                  }
                },
              ),
            );
          }

          if (supportedSlidingCounts.contains(4)) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: _slidingCountLabel(4, lang),
                icon: Icons.sync_alt_rounded,
                selected:
                    zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == 4,
                onPressed: () async {
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
                    await _setSelectedZoneSlidingSashesFromUi(4);
                  }
                },
              ),
            );
          }
        }
        if (isSlidingSupported &&
            (widget.systemMode == 'sliding' || widget.systemMode == 'mixed')) {
          for (final count in const [5, 6]) {
            if (!supportedSlidingCounts.contains(count)) continue;
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: _slidingCountLabel(count, lang),
                icon: Icons.sync_alt_rounded,
                selected:
                    zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == count,
                onPressed: () async {
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
                    await _setSelectedZoneSlidingSashesFromUi(count);
                  }
                },
              ),
            );
          }
        }
        if (zone.content == ZoneContent.slidingSash) {
          children.add(const SizedBox(width: 16));
          children.add(
            Text(
              _trackShortTitle(lang),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
          for (final count in supportedTrackCounts.toList()..sort()) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: _trackCountLabel(count, lang),
                icon: Icons.view_week_rounded,
                selected: zone.slidingTrackCount == count,
                onPressed: () =>
                    widget.model.setSelectedZoneSlidingTracks(count),
              ),
            );
          }
          if (zone.slidingSashesCount >= 4 &&
              zone.slidingSashesCount % 2 == 0) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: zone.slidingFaceToFace
                    ? 'التقاء الضلفتين الوسطيتين: مفعّل'
                    : 'التقاء الضلفتين الوسطيتين: غير مفعّل',
                icon: Icons.layers_rounded,
                selected: zone.slidingFaceToFace,
                onPressed: () {
                  setState(() {
                    widget.model.toggleSelectedZoneSlidingFaceToFace();
                  });
                },
              ),
            );
          }
          final supportsCacheRail =
              widget.model.getConfiguredSectionForRole(
                'cache_rail',
                useSlidingSeries: true,
              ) !=
              null;
          if (supportsCacheRail) {
            final cacheRailPerSide = math.max(0, zone.slidingTrackCount - 1);
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: widget.model.useOptionalCacheRail
                    ? 'كاش راي: $cacheRailPerSide يمين + $cacheRailPerSide يسار'
                    : 'كاش راي: غير مفعّل',
                icon: Icons.view_sidebar_rounded,
                selected: widget.model.useOptionalCacheRail,
                onPressed: () => widget.model.toggleCacheRail(
                  !widget.model.useOptionalCacheRail,
                ),
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
        final bool selectedZoneUsesSlidingFrame =
            zone.content == ZoneContent.slidingSash ||
            (widget.systemMode == 'sliding' &&
                zone.content != ZoneContent.empty &&
                zone.content != ZoneContent.fixedGlass);
        final bool selectedZoneUsesOpeningFrame =
            !selectedZoneUsesSlidingFrame &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash ||
                zone.content == ZoneContent.fixedGlass ||
                zone.content == ZoneContent.empty);
        final rawOpeningProfiles = selectedZoneUsesOpeningFrame
            ? (widget.systemMode == 'mixed'
                  ? _openingFrameProfiles
                  : (_openingFrameProfiles.isNotEmpty
                        ? _openingFrameProfiles
                        : _frameProfiles))
            : <Map<String, dynamic>>[];
        final openingProfiles = _filterFrameProfilesForDrawingRules(
          rawOpeningProfiles,
          series: widget.model.activeSeries,
          drawingMode: AccessoryDrawingMode.opening,
        );
        final rawSlidingProfiles = selectedZoneUsesSlidingFrame
            ? _slidingFrameProfiles
            : <Map<String, dynamic>>[];
        final slidingProfiles =
            _filterFrameProfilesForDrawingRules(
                  rawSlidingProfiles,
                  series: widget.model.effectiveSlidingSeries ??
                      widget.model.activeSlidingSeries,
                  drawingMode: AccessoryDrawingMode.sliding,
                )
                // The one-track profile is an automatic extension selected from
                // the series rules; it is not a replacement for the two-track
                // base frame and therefore must not be shown in this picker.
                .where(
                  (profile) => !widget.model.isSlidingFrameExtension(profile),
                )
                .toList();

        Future<void> selectFrameProfile(
          Map<String, dynamic> item, {
          required bool sliding,
        }) async {
          final mutableSelected = Map<String, dynamic>.from(item);
          mutableSelected['calculated_price'] =
              await _sectionPriceForSelectedColor(mutableSelected);
          setState(() {
            widget.model.applyFrameOverride(
              mutableSelected,
              sliding: sliding,
              manualSelection: true,
            );
            widget.model.updateProfileThickness();
            widget.model.refreshUI();
          });
          await widget.model.syncFrameReinforcement();
          if (mounted) setState(() {});
        }

        if (widget.model.getFrameRects().length > 1) {
          if (openingProfiles.isNotEmpty) {
            final current = widget.model.frameOverride;
            final hasIntegrated =
                current != null && profileHasIntegratedSideCover(current);
            final inProfiles =
                current != null &&
                openingProfiles.any((p) => p['id'] == current['id']);
            if (current == null || hasIntegrated || !inProfiles) {
              final plain = openingProfiles.firstWhere(
                (p) => !profileHasIntegratedSideCover(p),
                orElse: () => openingProfiles.first,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && widget.model.getFrameRects().length > 1) {
                  selectFrameProfile(plain, sliding: false);
                }
              });
            }
          }
          if (slidingProfiles.isNotEmpty) {
            final current = widget.model.slidingFrameOverride;
            final hasIntegrated =
                current != null && profileHasIntegratedSideCover(current);
            final inProfiles =
                current != null &&
                slidingProfiles.any((p) => p['id'] == current['id']);
            if (current == null || hasIntegrated || !inProfiles) {
              final plain = slidingProfiles.firstWhere(
                (p) => !profileHasIntegratedSideCover(p),
                orElse: () => slidingProfiles.first,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && widget.model.getFrameRects().length > 1) {
                  selectFrameProfile(plain, sliding: true);
                }
              });
            }
          }
        }

        final Map<String, dynamic>? activeOpeningFrameMap =
            widget.model.getFrameRects().length > 1 &&
                (widget.model.frameOverride == null ||
                    profileHasIntegratedSideCover(
                      widget.model.frameOverride!,
                    ) ||
                    !openingProfiles.any(
                      (p) => p['id'] == widget.model.frameOverride?['id'],
                    )) &&
                openingProfiles.isNotEmpty
            ? openingProfiles.firstWhere(
                (p) => !profileHasIntegratedSideCover(p),
                orElse: () => openingProfiles.first,
              )
            : widget.model.frameOverride;

        final Map<String, dynamic>? activeSlidingFrameMap =
            widget.model.getFrameRects().length > 1 &&
                (widget.model.slidingFrameOverride == null ||
                    profileHasIntegratedSideCover(
                      widget.model.slidingFrameOverride!,
                    ) ||
                    !slidingProfiles.any(
                      (p) =>
                          p['id'] == widget.model.slidingFrameOverride?['id'],
                    )) &&
                slidingProfiles.isNotEmpty
            ? slidingProfiles.firstWhere(
                (p) => !profileHasIntegratedSideCover(p),
                orElse: () => slidingProfiles.first,
              )
            : widget.model.getSlidingBaseFrameSection()?.toMap();

        void addFrameProfileButtons(
          List<Map<String, dynamic>> profiles, {
          required bool sliding,
          required String prefix,
        }) {
          for (var item in profiles) {
            final codeStr =
                (item['code'] != null && item['code'].toString().isNotEmpty)
                ? '${item['code']} - '
                : '';
            final nameStr = item['name'] ?? 'بدون اسم';
            final label = prefix.isEmpty
                ? '$codeStr$nameStr'
                : '$prefix: $codeStr$nameStr';
            final selectedMap = sliding
                ? activeSlidingFrameMap
                : activeOpeningFrameMap;
            final isSelected =
                selectedMap != null && selectedMap['id'] == item['id'];

            final button = Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ProfileButton(
                label: label,
                code: item['code']?.toString(),
                imagePath: item['image_path']?.toString(),
                selected: isSelected,
                onPressed: () => selectFrameProfile(item, sliding: sliding),
              ),
            );
            children.add(
              widget.systemMode == 'mixed'
                  ? _Tier2RowItem(rowIndex: sliding ? 1 : 0, child: button)
                  : button,
            );
          }
        }

        if (openingProfiles.isEmpty && slidingProfiles.isEmpty) {
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
          if (openingProfiles.isNotEmpty) {
            addFrameProfileButtons(
              openingProfiles,
              sliding: false,
              prefix: widget.systemMode == 'mixed' ? 'فتح' : '',
            );
          }
          if (slidingProfiles.isNotEmpty) {
            if (openingProfiles.isNotEmpty) {
              children.add(const SizedBox(width: 8));
            }
            addFrameProfileButtons(slidingProfiles, sliding: true, prefix: '');
          }
        }

        // زر الغطاء الجانبي (Side Cover toggle)
        children.add(const SizedBox(width: 8));
        final bool isNestedSlidingFrame = widget.model
            .isSlidingZoneNestedInSingleFrame(zone);
        if (isNestedSlidingFrame) {
          children.add(
            _ContentButton(
              label: widget.model.hasInternalSlidingSideCover
                  ? Localization.translate('إزالة غطاء الإطار المنزلق', lang)
                  : Localization.translate('إضافة غطاء الإطار المنزلق', lang),
              icon: widget.model.hasInternalSlidingSideCover
                  ? Icons.border_clear_rounded
                  : Icons.border_outer_rounded,
              selected: widget.model.hasInternalSlidingSideCover,
              onPressed: () {
                widget.model.toggleInternalSlidingSideCover(
                  !widget.model.hasInternalSlidingSideCover,
                );
                setState(() {});
              },
            ),
          );
        } else {
          children.add(
            _ContentButton(
              label: widget.model.hasSideCovers
                  ? Localization.translate('إزالة غطاء جانبي', lang)
                  : Localization.translate('إضافة غطاء جانبي', lang),
              icon: widget.model.hasSideCovers
                  ? Icons.border_clear_rounded
                  : Icons.border_outer_rounded,
              selected: widget.model.hasSideCovers,
              showWarning: false,
              onPressed: () async {
                await widget.model.toggleSideCovers(
                  !widget.model.hasSideCovers,
                );
                setState(() {});
              },
            ),
          );
        }

        // زر بروفيل الزاوية 90° (Profil d'angle / Tube carré 90°)
        children.add(const SizedBox(width: 8));
        children.add(
          _ContentButton(
            label: widget.model.usesProfileAngle
                ? Localization.translate(
                    'بروفيل زاوية 90°: ${widget.model.profileAngleModeName}',
                    lang,
                  )
                : Localization.translate('إضافة بروفيل زاوية 90°', lang),
            icon: Icons.square_foot_rounded,
            selected: widget.model.usesProfileAngle,
            onPressed: () {
              _showProfileAngleDialog(context);
            },
          ),
        );

        if (!widget.model.isPVC &&
            widget.model.canUseOpeningOnlyOptions &&
            selectedZoneUsesOpeningFrame) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: widget.model.hasFramePlintheBottom
                  ? 'حذف بلانت الإطار'
                  : 'إضافة بلانت للإطار',
              icon: Icons.border_bottom_rounded,
              selected: widget.model.hasFramePlintheBottom,
              onPressed: () {
                widget.model.toggleFramePlintheBottom(
                  !widget.model.hasFramePlintheBottom,
                );
                setState(() {});
              },
            ),
          );
        }

        final selectedFrameUsesSlidingSeries = selectedZoneUsesSlidingFrame;
        final selectedSeriesHasC =
            widget.model.getConfiguredSectionForRole(
              'seuil',
              useSlidingSeries: selectedFrameUsesSlidingSeries,
            ) !=
            null;
        if (selectedSeriesHasC) {
          final cIsRequired = widget.model.isConfiguredRoleRequired(
            'seuil',
            useSlidingSeries: selectedFrameUsesSlidingSeries,
          );
          final cIsEnabled = widget.model.usesFrameRole(
            'seuil',
            sliding: selectedFrameUsesSlidingSeries,
          );
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: 'Seuil',
              icon: Icons.horizontal_rule_rounded,
              selected: cIsEnabled,
              onPressed: () {
                if (cIsRequired) return;
                widget.model.toggleSeuil(!cIsEnabled);
                setState(() {});
              },
            ),
          );
        }
        break;

      case 2: // ورقة (Sash settings)
        final bool isSliding =
            widget.systemMode == 'sliding' ||
            (widget.systemMode == 'mixed' &&
                zone.content == ZoneContent.slidingSash);
        final expectedSashSeriesId = isSliding
            ? (widget.model.effectiveSlidingSeries?.id ??
                widget.model.activeSlidingSeries?.id)
            : widget.model.activeSeries?.id;
        final sashProfiles = isSliding
            ? (_slidingSashProfiles.isNotEmpty
                  ? _slidingSashProfiles
                  : (_loadedSeriesId == expectedSashSeriesId
                        ? _sashProfiles
                        : const <Map<String, dynamic>>[]))
            : (_openingSashProfiles.isNotEmpty
                  ? _openingSashProfiles
                  : (_loadedSeriesId == expectedSashSeriesId
                        ? _sashProfiles
                        : const <Map<String, dynamic>>[]));
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

        if (sashProfiles.isEmpty) {
          children.add(
            Text(
              Localization.translate('لا توجد درف متوفرة لهذه السلسلة', lang),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        } else if (isSliding) {
          List<Map<String, dynamic>> uniqueProfiles(
            Iterable<Map<String, dynamic>> profiles,
          ) {
            final seen = <String>{};
            return profiles.where((profile) {
              final key =
                  _catalogRowId(profile)?.toString() ??
                  '${profile['code'] ?? ''}|${profile['name'] ?? ''}';
              return seen.add(key);
            }).toList();
          }

          final lateralProfiles = uniqueProfiles(
            sashProfiles.where(
              (s) =>
                  _isSlidingMontantCandidate(s, central: false) &&
                  (!_pvcMontantReinforcementDisabled ||
                      !_isReinforcedMontant(s, central: false)),
            ),
          );

          final centralProfiles = uniqueProfiles(
            sashProfiles.where(
              (s) =>
                  _isSlidingMontantCandidate(s, central: true) &&
                  (!_pvcMontantReinforcementDisabled ||
                      !_isReinforcedMontant(s, central: true)),
            ),
          );
          final traverseProfiles = uniqueProfiles(
            sashProfiles.where((profile) {
              final type = '${profile['type'] ?? ''}'.toLowerCase();
              final name = '${profile['name'] ?? ''}'.toLowerCase();
              return type.contains('sash_traverse') ||
                  type.contains('traverse') ||
                  name.contains('traverse') ||
                  name.contains('ترافيرس');
            }),
          );
          final baseSashProfiles = uniqueProfiles(
            sashProfiles.where((profile) {
              final role = '${profile['design_role_key'] ?? ''}'
                  .trim()
                  .toLowerCase();
              final isMontant =
                  _isSlidingMontantCandidate(profile, central: false) ||
                  _isSlidingMontantCandidate(profile, central: true);
              final isTraverse = traverseProfiles.any(
                (candidate) =>
                    _catalogRowId(candidate) == _catalogRowId(profile),
              );
              final isSlim = widget.model.isSlidingMontantSlimCandidate(
                profile,
              );
              return !isMontant &&
                  !isTraverse &&
                  !isSlim &&
                  (role.isEmpty ||
                      role == 'sash' ||
                      role == 'sash_extension' ||
                      role == 'sliding_sash');
            }),
          );
          final slimProfiles = uniqueProfiles(
            widget.model.getSlidingSlimCandidates(),
          );

          if (baseSashProfiles.isNotEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  Localization.translate('الضلفة (Ouvrant):', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue,
                  ),
                ),
              ),
            );
            for (final item in baseSashProfiles) {
              final selected =
                  widget.model.slidingSashOverride?['id']?.toString() ==
                  item['id']?.toString();
              final code = '${item['code'] ?? ''}'.trim();
              final name = '${item['name'] ?? 'بدون اسم'}'.trim();
              children.add(
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProfileButton(
                    label: code.isEmpty ? name : '$code - $name',
                    code: item['code']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    selected: selected,
                    onPressed: () async {
                      final chosen = Map<String, dynamic>.from(item);
                      chosen['calculated_price'] =
                          await _sectionPriceForSelectedColor(chosen);
                      if (!mounted) return;
                      setState(() {
                        widget.model.applySashOverride(
                          chosen,
                          sliding: true,
                          manualSelection: true,
                        );
                        widget.model.refreshUI();
                      });
                    },
                  ),
                ),
              );
            }
            children.add(const SizedBox(width: 12));
          }

          bool isLateralSelected(Map<String, dynamic> item) {
            final String code = item['code']?.toString() ?? '';
            final String name = item['name']?.toString().toLowerCase() ?? '';
            final String type = item['type']?.toString().toLowerCase() ?? '';
            final bool itemIsReinforced =
                code.endsWith('108') ||
                name.contains('معزز') ||
                name.contains('renforc') ||
                type.contains('renforc') ||
                widget.model.isSlidingMontantReinforced(item, central: false);

            final current =
                widget.model.componentOverrides[itemIsReinforced
                    ? 'قائم جانبي معزز (Sash Lateral Renforcé)'
                    : 'قائم جانبي (Sash Lateral)'] ??
                (!itemIsReinforced
                    ? widget.model.componentOverrides['قائم جانبي (Lateral)']
                    : null);
            if (current is Map &&
                current['id']?.toString() == '${item['id']}') {
              return true;
            }

            final bool hasLateralReinforced =
                !_pvcMontantReinforcementDisabled &&
                widget.model.zones.any(
                  (z) =>
                      z.slidingMontantReinforced['lateral_0'] == true ||
                      z.slidingMontantReinforced['lateral_1'] == true,
                );
            final bool hasLateralNormal = widget.model.zones.any(
              (z) =>
                  z.content == ZoneContent.slidingSash &&
                  (z.slidingMontantReinforced['lateral_0'] != true ||
                      z.slidingMontantReinforced['lateral_1'] != true),
            );

            if (itemIsReinforced) {
              return hasLateralReinforced;
            } else {
              return hasLateralNormal;
            }
          }

          bool isCentralSelected(Map<String, dynamic> item) {
            // A slim central member visually replaces the chicane at that
            // junction. Keep the catalogue selection intact for geometry,
            // but do not leave a Chicane button highlighted beside Slim.
            final role = '${item['design_role_key'] ?? ''}'
                .trim()
                .toLowerCase();
            final itemText = '${item['name'] ?? ''} ${item['type'] ?? ''}'
                .toLowerCase();
            final isChicane =
                role == 'chicane' ||
                itemText.contains('chicane') ||
                itemText.contains('شيكان');
            final hasSlimCentral = widget.model.zones.any(
              (zone) => zone.slidingMontantSlim.values.any((value) => value),
            );
            if (isChicane && hasSlimCentral) return false;

            final String code = item['code']?.toString() ?? '';
            final String name = item['name']?.toString().toLowerCase() ?? '';
            final String type = item['type']?.toString().toLowerCase() ?? '';
            final bool itemIsReinforced =
                code.endsWith('107') ||
                name.contains('معزز') ||
                name.contains('renforc') ||
                type.contains('renforc') ||
                widget.model.isSlidingMontantReinforced(item, central: true);

            final current =
                widget.model.componentOverrides[itemIsReinforced
                    ? 'قائم وسطي معزز (Sash Central Renforcé)'
                    : 'قائم وسطي (Sash Central)'] ??
                (!itemIsReinforced
                    ? widget.model.componentOverrides['قائم وسطي (Central)']
                    : null);
            if (current is Map &&
                current['id']?.toString() == '${item['id']}') {
              return true;
            }

            bool hasCentralReinforced = false;
            bool hasCentralNormal = false;
            for (final z in widget.model.zones) {
              if (z.content != ZoneContent.slidingSash) continue;
              final sashes = z.slidingSashesCount > 0
                  ? z.slidingSashesCount
                  : 2;
              final centralCount = math.max(0, (sashes * 2) - 2);
              for (var i = 0; i < centralCount; i++) {
                if (!_pvcMontantReinforcementDisabled &&
                    z.slidingMontantReinforced['central_$i'] == true) {
                  hasCentralReinforced = true;
                } else {
                  hasCentralNormal = true;
                }
              }
            }

            if (itemIsReinforced) {
              return hasCentralReinforced;
            } else {
              return hasCentralNormal;
            }
          }

          void selectLateral(Map<String, dynamic> item) async {
            final mutableSelected = Map<String, dynamic>.from(item);
            mutableSelected['calculated_price'] =
                await _sectionPriceForSelectedColor(mutableSelected);

            setState(() {
              widget.model.applySlidingMontantOverride(
                mutableSelected,
                central: false,
                manualSelection: true,
              );
              widget.model.refreshUI();
            });
          }

          void selectCentral(Map<String, dynamic> item) async {
            final mutableSelected = Map<String, dynamic>.from(item);
            mutableSelected['calculated_price'] =
                await _sectionPriceForSelectedColor(mutableSelected);
            final role = '${item['design_role_key'] ?? ''}'
                .trim()
                .toLowerCase();
            final itemText = '${item['name'] ?? ''} ${item['type'] ?? ''}'
                .toLowerCase();
            final isChicane =
                role == 'chicane' ||
                itemText.contains('chicane') ||
                itemText.contains('شيكان');

            setState(() {
              // Chicane and montant central slim are mutually exclusive.
              // Clearing only the per-zone choice restores the normal/chicane
              // sash drawing while keeping the catalog selection available for
              // a later explicit Slim selection.
              if (isChicane) {
                for (final zone in widget.model.zones) {
                  if (zone.content != ZoneContent.slidingSash) continue;
                  for (final key in zone.slidingMontantSlim.keys.toList()) {
                    zone.slidingMontantSlim[key] = false;
                  }
                }
              }
              widget.model.applySlidingMontantOverride(
                mutableSelected,
                central: true,
                manualSelection: true,
              );
              widget.model.refreshUI();
            });
          }

          final bool hasThreePieceSliding =
              (widget.model.effectiveSlidingSeries?.hasThreePieceSash ??
                  widget.model.activeSlidingSeries?.hasThreePieceSash ??
                  false) ||
              '${widget.model.effectiveSlidingSeries?.name ?? widget.model.activeSlidingSeries?.name ?? ''}'
                  .toLowerCase()
                  .contains('tpr');

          if (hasThreePieceSliding && lateralProfiles.isNotEmpty) {
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
                  (item['code'] != null && item['code'].toString().isNotEmpty)
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
          }

          if (hasThreePieceSliding && centralProfiles.isNotEmpty) {
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
                  (item['code'] != null && item['code'].toString().isNotEmpty)
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
          }
          if (traverseProfiles.isNotEmpty) {
            children.add(const SizedBox(width: 12));
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  Localization.translate('سكة الظلفة (Sash Traverse)', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue,
                  ),
                ),
              ),
            );
            for (final item in traverseProfiles) {
              final selected =
                  widget
                      .model
                      .componentOverrides['سكة الظلفة (Sash Traverse)']?['id']
                      ?.toString() ==
                  item['id']?.toString();
              children.add(
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProfileButton(
                    label: '${item['code'] ?? ''} - ${item['name'] ?? ''}',
                    code: item['code']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    selected: selected,
                    onPressed: () async {
                      final chosen = Map<String, dynamic>.from(item);
                      chosen['calculated_price'] =
                          await _sectionPriceForSelectedColor(chosen);
                      setState(() {
                        widget
                                .model
                                .componentOverrides['سكة الظلفة (Sash Traverse)'] =
                            chosen;
                        widget.model.refreshUI();
                      });
                    },
                  ),
                ),
              );
            }
          }
          if (slimProfiles.isNotEmpty) {
            children.add(const SizedBox(width: 12));
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  Localization.translate('المونتوسليم (Montant Slim):', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue,
                  ),
                ),
              ),
            );
            final activeSlimProfile =
                widget.model.selectedSlimMontantProfile ?? slimProfiles.first;
            for (final item in slimProfiles) {
              final selected =
                  activeSlimProfile['id']?.toString() == item['id']?.toString();
              children.add(
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProfileButton(
                    label: '${item['code'] ?? ''} - ${item['name'] ?? ''}',
                    code: item['code']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    selected: selected,
                    onPressed: () async {
                      final chosen = Map<String, dynamic>.from(item);
                      chosen['calculated_price'] =
                          await _sectionPriceForSelectedColor(chosen);
                      setState(() {
                        widget.model.applySlidingMontantSlimOverride(chosen);
                        widget.model.refreshUI();
                      });
                    },
                  ),
                ),
              );
            }
          }
        } else {
          for (var item in sashProfiles) {
            final codeStr =
                (item['code'] != null && item['code'].toString().isNotEmpty)
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
                    final mutableSelected = Map<String, dynamic>.from(item);
                    mutableSelected['calculated_price'] =
                        await _sectionPriceForSelectedColor(mutableSelected);
                    setState(() {
                      widget.model.applySashOverride(
                        mutableSelected,
                        sliding: false,
                        manualSelection: true,
                      );
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
              (dir) => Padding(
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
          if (zone.slidingSashesCount >= 4 &&
              zone.slidingSashesCount % 2 == 0) {
            if (widget.model.supportsSlidingFaceToFace) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: Localization.translate(
                    'التقاء الوسط (Face-to-Face)',
                    lang,
                  ),
                  icon: Icons.layers_rounded,
                  selected: zone.slidingFaceToFace,
                  onPressed: () {
                    setState(() {
                      widget.model.toggleSelectedZoneSlidingFaceToFace();
                    });
                  },
                ),
              );
            }
            if (zone.slidingFaceToFace ||
                (zone.slidingSashesCount == 6 && zone.slidingTrackCount == 3)) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: 'مقبض وسط الضلفتين',
                  icon: Icons.more_horiz_rounded,
                  selected: zone.slidingCentralHandle,
                  onPressed: () {
                    setState(() {
                      widget.model.toggleSelectedZoneSlidingCentralHandle();
                    });
                  },
                ),
              );
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: 'مقبض الوسط الثاني (شكلي)',
                  icon: Icons.more_horiz_outlined,
                  selected: zone.slidingSecondCentralHandle,
                  onPressed: () {
                    if (!zone.slidingCentralHandle) return;
                    setState(() {
                      widget.model
                          .toggleSelectedZoneSlidingSecondCentralHandle();
                    });
                  },
                ),
              );
            }
          }
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
                            (dir) => Padding(
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
              "${widget.model.selection.isHorizontalMullion! ? 'H' : 'V'}_${widget.model.selection.mullionPosition!.toStringAsFixed(1)}";
          MullionProfileType currentType =
              widget.model.mullionProfiles[key] ?? MullionProfileType.standard;
          final canFlipGroove =
              currentType == MullionProfileType.grooved &&
              widget.model.selection.isHorizontalMullion != null &&
              widget.model.selection.mullionPosition != null;

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
              showSubmenuIndicator: true,
              onPressed: () => _showMullionFrameSelectorDialog(
                context,
                MullionProfileType.flat,
              ),
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: 'Cadre 140',
              icon: Icons.view_headline_rounded,
              selected: currentType == MullionProfileType.grooved,
              showSubmenuIndicator: true,
              onPressed: () => _showMullionFrameSelectorDialog(
                context,
                MullionProfileType.grooved,
              ),
            ),
          );
          if (canFlipGroove) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: 'قلب جهة حامل الزجاج',
                icon: Icons.swap_horiz_rounded,
                selected: widget.model.isGroovedMullionCavityOnPositiveSide(
                  widget.model.selection.isHorizontalMullion!,
                  widget.model.selection.mullionPosition!,
                ),
                onPressed: () {
                  setState(() {
                    widget.model.toggleGroovedMullionCavity(
                      widget.model.selection.isHorizontalMullion!,
                      widget.model.selection.mullionPosition!,
                    );
                  });
                },
              ),
            );
          }
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
              ? '${Localization.translate('Parclose', lang)}: ${parcloseOverride['code']} (${(parcloseOverride['max_glass_thickness'] as num?)?.toDouble() ?? 0.0} ${Localization.translate('مم', lang)})'
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
            final double tOuter =
                spec.thicknessOuter ?? kDefaultGlassPaneThickness;
            final int intercall = spec.intercallThickness;
            final double tInner =
                spec.thicknessInner ?? kDefaultGlassPaneThickness;
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

        final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    '${Localization.translate('الزجاج الحالي', lang)}: $glassDesc',
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
            children.add(_buildRuleHandles(zone));
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
    final lang = Provider.of<AppSettingsProvider>(context).language;

    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                      : '${Localization.translate('المنطقة المحددة', lang)}: ${Localization.translate(zone.content.name, lang)}  |  ${Localization.translate('الأبعاد', lang)}: ${zone.boundary.width.toInt()} × ${zone.boundary.height.toInt()} mm',
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
                          onPressed: () =>
                              _openMaterialConsumptionScreen(context),
                          child: Text(
                            Localization.translate('الكمية والتكلفة', lang),
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

  Future<void> _openMaterialConsumptionScreen(BuildContext context) async {
    if (widget.model.zones.any(
      (zone) =>
          zone.glass.glazingFitValid == false ||
          zone.cellGlassSpec.values.any(
            (spec) => spec.glazingFitValid == false,
          ),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تركيب الزجاج غير متوافق. راجع السماكات والجوانات في القائمة اليسرى قبل اعتماد الكمية والتكلفة.',
          ),
        ),
      );
      return;
    }
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final hasWindowContent = widget.model.zones.any(
      (z) => z.content != ZoneContent.empty,
    );
    final hasReadyShutterOnly =
        widget.model.isShutterOnly &&
        widget.model.width > 0 &&
        widget.model.height > 0;

    if (!hasReadyShutterOnly && !hasWindowContent) {
      final message = widget.model.drawNextShapeAsShutterOnly
          ? 'ارسم مستطيل الستار على اللوحة أولاً قبل حساب الكمية والتكلفة.'
          : 'الرجاء رسم أو إضافة جزء في النافذة أولاً قبل حساب التكلفة!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate(message, lang)),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    widget.model.clearSelection();

    if (!widget.model.isShutterOnly) {
      // The frame picked in the drawing is the source of truth. Refresh its
      // colour price in the background so database startup never blocks the
      // transition to the material table.
      unawaited(() async {
        try {
          final activeFrame = widget.model.activeFrameOverride;
          final cId = _selectedProfileColorId();
          if (activeFrame == null || cId == null) return;
          final rawFrameId = activeFrame['id'];
          final sId = rawFrameId is num
              ? rawFrameId.toInt()
              : int.tryParse(rawFrameId?.toString() ?? '');
          if (sId == null) return;

          final updatedPrice = await SqlDatabase().getSectionPrice(sId, cId);
          final pricedFrame = Map<String, dynamic>.from(activeFrame);
          pricedFrame['calculated_price'] = updatedPrice;
          if (widget.model.usesSlidingPrimaryProfiles) {
            widget.model.slidingFrameOverride = pricedFrame;
          } else {
            widget.model.frameOverride = pricedFrame;
            widget.model.selectedFrameCode = pricedFrame['code']?.toString();
          }
          widget.model.updateProfileThickness();
        } catch (error) {
          debugPrint('Failed to refresh frame price in background: $error');
        }
      }());
    }

    if (!context.mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MaterialConsumptionScreen(model: widget.model),
      ),
    );
    if (result == true && context.mounted) {
      Navigator.pop(context, widget.model);
    }
  }

  void _showParcloseSelectorDialog(BuildContext context) async {
    final dbInstance = SqlDatabase();
    final d = await dbInstance.db;
    if (d == null || activeSeriesForSystem == null) return;

    final List<Map<String, dynamic>> res = await d.query(
      'Sections',
      where:
          'series_id = ? AND (type = ? OR type LIKE ? OR name LIKE ? OR TRIM(code) = ?)',
      whereArgs: [
        activeSeriesForSystem!.id,
        'parclose',
        '%parclose%',
        '%باكيت%',
        '514',
      ],
      orderBy: "CASE WHEN TRIM(code) = '514' THEN 0 ELSE 1 END, id",
    );

    // A double glazing pack must only be paired with a parclose that leaves
    // room for a real Intercall. Filter invalid single/small parcloses from
    // this selector so they cannot be chosen after the automatic selection.
    var requiredDoubleThickness = 0.0;
    void considerGlass(GlassSpecification glass) {
      if (glass.structure != GlassStructure.double) return;
      final total = glass.totalThickness(widget.model.allGlassCache);
      if (total > requiredDoubleThickness) requiredDoubleThickness = total;
    }

    for (final zone in widget.model.zones) {
      considerGlass(zone.glass);
      for (final glass in zone.cellGlassSpec.values) {
        considerGlass(glass);
      }
    }
    final simple514 = res
        .where((item) => item['code']?.toString().trim() == '514')
        .toList();
    final availableParcloses = requiredDoubleThickness > 0
        ? res.where((item) {
            final raw = item['max_glass_thickness'];
            final capacity = raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '');
            return (capacity ?? 0) >=
                (requiredDoubleThickness > 10.0
                    ? requiredDoubleThickness
                    : 10.0);
          }).toList()
        : (simple514.isNotEmpty ? simple514 : res);

    if (!context.mounted) return;

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

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
                          '${Localization.translate('السمك الأقصى للزجاج', lang)}: $maxThickness ${Localization.translate('مم', lang)}',
                        ),
                        trailing: Icon(
                          widget.model.componentOverrides['باكيت الزجاج (Parclose)']?['id'] ==
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
                          widget.model
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

  const _IntercallButton({
    required this.thickness,
    required this.selected,
    required this.onPressed,
    this.showWarning = false,
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

  const _ContentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.showWarning = false,
    this.showSubmenuIndicator = false,
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
                    : (selected ? Colors.blue.shade900 : Colors.grey.shade800),
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
                    : (selected ? Colors.blue.shade900 : Colors.grey.shade600),
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

    if (model.width > 0 &&
        model.height > 0 &&
        (model.zones.isNotEmpty || model.isShutterOnly)) {
      final painter = WindowPainter(
        model: model,
        showDrawingDimensions: true,
        showSelection: true,
      );
      painter.paint(canvas, size);
      // Keep the exterior dimensions outside the frame, then add compact
      // editable region labels and profile cut labels inside the drawing.
      _paintDimensions(canvas, model, Offset.zero);
      if (!model.isShutterOnly) {
        _paintZoneRegionDimensions(canvas, model);
        _paintDrawingProfileDimensions(canvas, model);
      }

      final selectedFrameKey = model.selection.type == SelectionType.frame
          ? model.selection.zoneId
          : null;
      if (selectedFrameKey != null) {
        final frameRect = model.frameRectForSelection(selectedFrameKey);
        if (frameRect != null) {
          final side = 18.0 / (model.canvasScale * userScale);
          final outline = Paint()
            ..color = Colors.green.shade700
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0 / (model.canvasScale * userScale);
          final fill = Paint()
            ..color = Colors.green.shade600
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

      if (model.canBeArchedOrSlanted &&
          model.selection.type == SelectionType.frame &&
          (model.selection.zoneId == null ||
              model.selection.zoneId == 'frame:0' ||
              model.getFrameRects().length <= 1)) {
        final double radius = 10.0 / (model.canvasScale * userScale);
        final fillPaint = Paint()
          ..color = Colors.amber.shade800
          ..style = PaintingStyle.fill;
        final innerPaint = Paint()
          ..color = Colors.amber.shade300
          ..style = PaintingStyle.fill;
        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / (model.canvasScale * userScale);
        final shadowPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill;

        void drawHandle(Offset center) {
          canvas.drawCircle(
            center + Offset(0, 1.5 / (model.canvasScale * userScale)),
            radius,
            shadowPaint,
          );
          canvas.drawCircle(center, radius, fillPaint);
          canvas.drawCircle(center, radius * 0.45, innerPaint);
          canvas.drawCircle(center, radius, borderPaint);
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
            fontWeight: FontWeight.w800,
            shadows: const [
              Shadow(color: Color(0xCCFFFFFF), blurRadius: 2.5),
              Shadow(
                color: Color(0x55000000),
                blurRadius: 1.5,
                offset: Offset(0, 0.7),
              ),
            ],
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
          cutLabel(frameWidth, effectiveFrameCode),
          Rect.fromLTWH(
            frame.left + 2,
            frame.top + 1,
            math.max(0.0, frame.width - 4),
            math.max(0.0, frameThickness - 2),
          ),
        );
        _paintProfileDimensionLabel(
          canvas,
          cutLabel(frameHeight, effectiveFrameCode),
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
            fontWeight: FontWeight.w800,
            shadows: const [
              Shadow(color: Color(0xCCFFFFFF), blurRadius: 2.5),
              Shadow(
                color: Color(0x55000000),
                blurRadius: 1.5,
                offset: Offset(0, 0.7),
              ),
            ],
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

  void _paintDimensions(Canvas canvas, WindowModel model, Offset pos) {
    final double scW = model.sideCoverWidth;
    final physicalFrames = model.getPhysicalFrameInfos();
    final bool isMultiFrame = physicalFrames.length > 1;
    final sortedFrames = List<PhysicalFrameInfo>.from(physicalFrames)
      ..sort((a, b) => a.rect.left != b.rect.left
          ? a.rect.left.compareTo(b.rect.left)
          : a.rect.top.compareTo(b.rect.top));

    final bool hasVaryingHeights = isMultiFrame &&
        sortedFrames.any((f) => (f.rect.height - sortedFrames.first.rect.height).abs() > 1.0);

    double offsetDistTop = isMultiFrame ? 105.0 : 60.0;
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
    double offsetDistRight = 50.0;
    if (model.hasSideCovers && !model.removedShutterSides.contains('right')) {
      offsetDistRight += scW + 15.0;
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

    // --- Width Dimensions ---
    // Outer/Total width
    _drawDimension(
      canvas,
      '${model.width.toInt()} mm',
      Offset(pos.dx, widthY),
      Offset(pos.dx + model.width, widthY),
      isVerticalLine: false,
    );
    // Witness lines for total width
    _drawWitnessLine(
      canvas,
      Offset(pos.dx, pos.dy),
      Offset(pos.dx, widthY - 8.0),
    );
    _drawWitnessLine(
      canvas,
      Offset(pos.dx + model.width, pos.dy),
      Offset(pos.dx + model.width, widthY - 8.0),
    );

    // If multi-frame, draw individual frame widths on Layer 1
    if (isMultiFrame) {
      double layer1Y = isSlantedOrArched ? widthY : widthY + 45.0;
      for (final f in sortedFrames) {
        final double x0 = pos.dx + f.rect.left;
        final double x1 = pos.dx + f.rect.right;
        _drawDimension(
          canvas,
          '${f.rect.width.toInt()} mm',
          Offset(x0, layer1Y),
          Offset(x1, layer1Y),
          isVerticalLine: false,
          isSmall: true,
        );
        // Vertical witness ticks connecting to frame
        _drawWitnessLine(
          canvas,
          Offset(x0, pos.dy + f.rect.top),
          Offset(x0, layer1Y - 6.0),
        );
        _drawWitnessLine(
          canvas,
          Offset(x1, pos.dy + f.rect.top),
          Offset(x1, layer1Y - 6.0),
        );
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
        );
      }

      // Leftmost frame height on the left
      final leftmost = sortedFrames.first;
      final double leftStartY = pos.dy + leftmost.rect.top;
      final double leftEndY = pos.dy + leftmost.rect.bottom;
      final double leftDimX = pos.dx - offsetDistLeft;
      _drawDimension(
        canvas,
        '${leftmost.rect.height.toInt()} mm',
        Offset(leftDimX, leftStartY),
        Offset(leftDimX, leftEndY),
        isVerticalLine: true,
      );
      // Witness lines for leftmost frame
      _drawWitnessLine(
        canvas,
        Offset(pos.dx + leftmost.rect.left, leftStartY),
        Offset(leftDimX - 10.0, leftStartY),
      );
      _drawWitnessLine(
        canvas,
        Offset(pos.dx + leftmost.rect.left, leftEndY),
        Offset(leftDimX - 10.0, leftEndY),
      );

      // If leftmost frame is shorter than overall window height, show overall height on outer tier
      if (hasVaryingHeights && model.height > leftmost.rect.height + 1.0) {
        final double totalDimX = leftDimX - 50.0;
        _drawDimension(
          canvas,
          '${model.height.toInt()} mm',
          Offset(totalDimX, pos.dy),
          Offset(totalDimX, pos.dy + model.height),
          isVerticalLine: true,
        );
        _drawWitnessLine(
          canvas,
          Offset(pos.dx, pos.dy),
          Offset(totalDimX - 10.0, pos.dy),
        );
        _drawWitnessLine(
          canvas,
          Offset(pos.dx, pos.dy + model.height),
          Offset(totalDimX - 10.0, pos.dy + model.height),
        );
      }

      // Rightmost frame height on the right
      final rightmost = sortedFrames.last;
      final double rightStartY = pos.dy + rightmost.rect.top;
      final double rightEndY = pos.dy + rightmost.rect.bottom;
      final double rightDimX = pos.dx + model.width + offsetDistRight;
      _drawDimension(
        canvas,
        '${rightmost.rect.height.toInt()} mm',
        Offset(rightDimX, rightStartY),
        Offset(rightDimX, rightEndY),
        isVerticalLine: true,
      );
      // Witness lines for rightmost frame
      _drawWitnessLine(
        canvas,
        Offset(pos.dx + rightmost.rect.right, rightStartY),
        Offset(rightDimX + 10.0, rightStartY),
      );
      _drawWitnessLine(
        canvas,
        Offset(pos.dx + rightmost.rect.right, rightEndY),
        Offset(rightDimX + 10.0, rightEndY),
      );

      // Intermediate frames (index 1 to length - 2):
      // Draw vertical dimension line with start-to-end arrows inside the frame, off-center
      if (sortedFrames.length >= 3 && hasVaryingHeights) {
        for (int i = 1; i < sortedFrames.length - 1; i++) {
          final fInfo = sortedFrames[i];
          final double dimX = pos.dx + fInfo.rect.left + math.min(fInfo.rect.width * 0.28, 65.0);
          final double startY = pos.dy + fInfo.rect.top;
          final double endY = pos.dy + fInfo.rect.bottom;
          _drawDimension(
            canvas,
            '${fInfo.rect.height.toInt()} mm',
            Offset(dimX, startY),
            Offset(dimX, endY),
            isVerticalLine: true,
            isSmall: true,
          );
        }
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
  }

  void _drawWitnessLine(Canvas canvas, Offset p1, Offset p2) {
    final p = Paint()
      ..color = Colors.blueGrey.shade400.withOpacity(0.55)
      ..strokeWidth = 1.2;
    canvas.drawLine(p1, p2, p);
  }

  void _drawDimension(
    Canvas canvas,
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

  double _drawText(
    Canvas canvas,
    String text,
    Offset center, {
    bool isVertical = false,
    bool isSmall = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF0F172A),
          fontWeight: FontWeight.w800,
          fontSize: isSmall ? 46 : 66,
          shadows: const [
            Shadow(color: Color(0xCCFFFFFF), blurRadius: 3),
            Shadow(
              color: Color(0x55000000),
              blurRadius: 1.5,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (isVertical) canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    return tp.width;
  }

  void _drawArrow(
    Canvas canvas,
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

      // Arrowheads pointing to ends
      const double arrowLen = 12.0;
      const double arrowW = 4.5;
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
      const double arrowLen = 12.0;
      const double arrowW = 4.5;
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
        oldDelegate.userPan != userPan;
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

// Helper validation functions for sliding system glass/gasket thickness constraints (e.g. TPR 67000)
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
  if (isSliding && model.isSliding67Family) {
    final double minGasket = spec.jointTwoSides ? 4.0 : 2.0;
    final double maxAllowed = 24.0 - minGasket; // 20.0 or 22.0
    if (thickVal > maxAllowed) return false;
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
  if (isSliding && model.isSliding67Family) {
    final double minGasket = jointTwoSides ? 4.0 : 2.0;
    final double maxAllowed = 24.0 - minGasket; // 20.0 or 22.0
    if ((thickOuter + intercall + thickInner) > maxAllowed) return false;
  }
  return true;
}
