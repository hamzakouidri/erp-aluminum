import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';

enum GlassWorkType {
  showerCabin,
  vitrineSingleDoor,
  vitrineDoubleDoor,
  slidingShowerCabin,
  singleDoorShowerCabin,
}

enum _SablageMode { none, full, decorative }

class TemperedGlassWorkScreen extends StatefulWidget {
  const TemperedGlassWorkScreen({super.key, this.initialPayload});

  // Kept so existing navigation calls continue to compile. The new drawing
  // starts empty and deliberately does not restore an old glass-work payload.
  final Map<String, dynamic>? initialPayload;

  @override
  State<TemperedGlassWorkScreen> createState() =>
      _TemperedGlassWorkScreenState();
}

class _TemperedGlassWorkScreenState extends State<TemperedGlassWorkScreen> {
  // Initial workshop values. Keep these in one place so they can later be
  // moved to the workshop settings screen without changing the drawing code.
  static const _defaultHoleDiameterMm = 20.0;
  static const _defaultDoorHeightIncreaseMm = 30.0;
  static const _defaultFixedWidthIncreaseMm = 30.0;
  static const _freehandMaxWidthMm = 3000.0;
  static const _freehandMaxHeightMm = 3500.0;
  static const _slidingVisualGapPx = 2.0;
  static const _doorTopHoleSideOffsetMm = 80.0;
  static const _doorTopHoleTopOffsetMm = 35.0;
  static const _handleHoleEdgeOffsetMm = 50.0;
  static const _handleHoleSpacingMm = 200.0;
  static const _towelHoleSpacingMm = 400.0;

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
  String _glassType = 'normal';
  bool _glassTempered = true;
  String _edgeFinish = 'smooth';
  bool _doorOnLeft = true;

  bool get _isSlidingStraight => _workType == GlassWorkType.slidingShowerCabin;

  bool _isCompactLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 700.0;

  String _edgeFinishLabel(String value) {
    return switch (value) {
      'sharp' => _tr('حواف حادة', 'Bords vifs', 'Sharp edges'),
      _ => _tr('حواف ناعمة', 'Bords adoucis', 'Smooth edges'),
    };
  }

  String _glassTypeLabel(String value) {
    return switch (value) {
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
        holeDiameterMm: _holeDiameterMm,
        holeOverrides: _holeOverrides,
        sablageMode: _sablageMode,
        sablageRangeMode: _sablageRangeMode,
        sablageFromBottom: _sablageFromBottom,
        glassThicknessMm: _glassThicknessMm,
        doorOnLeft: _doorOnLeft,
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
    _holeDiameterMm = snapshot.holeDiameterMm;
    _holeOverrides
      ..clear()
      ..addAll(snapshot.holeOverrides.map((key, value) => MapEntry(key, value.copy())));
    _sablageMode = snapshot.sablageMode;
    _sablageRangeMode = snapshot.sablageRangeMode;
    _sablageFromBottom = snapshot.sablageFromBottom;
    _glassThicknessMm = snapshot.glassThicknessMm;
    _doorOnLeft = snapshot.doorOnLeft;
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
          holeDiameterMm: _holeDiameterMm,
          holeOverrides: _holeOverrides,
          sablageMode: _sablageMode,
          sablageRangeMode: _sablageRangeMode,
          sablageFromBottom: _sablageFromBottom,
          glassThicknessMm: _glassThicknessMm,
          doorOnLeft: _doorOnLeft,
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
          holeDiameterMm: _holeDiameterMm,
          holeOverrides: _holeOverrides,
          sablageMode: _sablageMode,
          sablageRangeMode: _sablageRangeMode,
          sablageFromBottom: _sablageFromBottom,
          glassThicknessMm: _glassThicknessMm,
          doorOnLeft: _doorOnLeft,
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

  @override
  void dispose() {
    _doorWidthController.dispose();
    _sablageBandWidthController.dispose();
    _sablageTransparentWidthController.dispose();
    _sablageCountController.dispose();
    _sablageStartController.dispose();
    _sablageEndController.dispose();
    super.dispose();
  }

  String _tr(String ar, String fr, String en) {
    final language = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final translated = Localization.translate(ar, language);
    if (language == AppLanguage.arabic || translated != ar) return translated;
    return switch (language) {
      AppLanguage.french => fr,
      AppLanguage.english => en,
      AppLanguage.arabic => ar,
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
    if (_panels.isEmpty) {
      return _tr('إدخال القياسات', 'Saisir les mesures', 'Enter measurements');
    }
    if (_isSlidingStraight && _overallDrawingRect != null) {
      return '${_overallWidthMm.toStringAsFixed(0)} × '
          '${_overallHeightMm.toStringAsFixed(0)} mm';
    }
    if (_panels.length == 1) {
      final panel = _panels.first;
      return '${panel.widthMm.toStringAsFixed(0)} × '
          '${panel.heightMm.toStringAsFixed(0)} mm';
    }
    return _tr(
      '${_panels.length} قياسات',
      '${_panels.length} mesures',
      '${_panels.length} measurements',
    );
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
          _GlassPanel(
            rect: panel,
            widthMm: widthMm,
            heightMm: heightMm,
          ),
        );
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
        final horizontalHoleEdge = holePosition.dx +
            (fromLeft ? -holeRadius : holeRadius);
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
        final verticalHoleEdge = holePosition.dy +
            (fromTop ? -holeRadius : holeRadius);
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

  void _handleCanvasTap(TapUpDetails details) {
    final position = _canvasPosition(details.localPosition);
    final target = _findMovableHole(position);
    if (target != null) {
      _editMovableHole(target);
      return;
    }
    if (_isExternalDimensionTap(position)) {
      _editMeasurements();
      return;
    }
    final panelIndex = _panels.lastIndexWhere(
      (panel) => panel.rect.contains(position),
    );
    setState(() => _selectedPanelIndex = panelIndex < 0 ? null : panelIndex);
  }

  bool _isExternalDimensionTap(Offset position) {
    for (final panel in _panels) {
      final horizontalDimensionHitBox = Rect.fromLTRB(
        panel.rect.left - 24,
        panel.rect.top - 44,
        panel.rect.right + 24,
        panel.rect.top - 4,
      );
      if (horizontalDimensionHitBox.contains(position)) return true;

      final verticalOnLeft = panel.role == 'door' &&
          _panels.any(
            (other) =>
                other.role == 'fixed' &&
                panel.rect.center.dx < other.rect.center.dx,
          );
      final dimensionX = verticalOnLeft
          ? panel.rect.left - 18
          : panel.rect.right + 18;
      final verticalDimensionHitBox = Rect.fromLTRB(
        dimensionX - 36,
        panel.rect.top - 20,
        dimensionX + 36,
        panel.rect.bottom + 20,
      );
      if (verticalDimensionHitBox.contains(position)) return true;
    }
    return false;
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
    final fixedWidth =
        practicalWidth - doorWidth + _fixedWidthCompensation();
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
    if (_canvasSize != Size.zero && doorTop < 8) {
      layoutRect = layoutRect.shift(Offset(0, 8 - doorTop));
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
    return [
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
      _GlassHole(
        xMm: safeX(_handleEdgeOffsetMm),
        yMm: safeY(topAllowanceMm + middleY - _handleSpacingMm / 2),
        diameterMm: _holeDiameterMm,
        purpose: 'handle_top',
      ),
      _GlassHole(
        xMm: safeX(_handleEdgeOffsetMm),
        yMm: safeY(topAllowanceMm + middleY + _handleSpacingMm / 2),
        diameterMm: _holeDiameterMm,
        purpose: 'handle_bottom',
      ),
    ]
        .map(
          (hole) => _applyHoleOverride(
            hole,
            widthMm: widthMm,
            heightMm: heightMm,
          ),
        )
        .toList();
  }

  List<_GlassHole> _fixedHoles(double widthMm, double heightMm) {
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
          (hole) => _applyHoleOverride(
            hole,
            widthMm: widthMm,
            heightMm: heightMm,
          ),
        )
        .toList();
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
    final xController = TextEditingController(text: hole.xMm.toStringAsFixed(0));
    final yController = TextEditingController(text: hole.yMm.toStringAsFixed(0));
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
          TextField field(TextEditingController controller, String label) {
            return TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: label,
                suffixText: 'mm',
                border: const OutlineInputBorder(),
              ),
            );
          }

          return AlertDialog(
            title: Text(
              _tr('تعديل الثقب', 'Modifier le trou', 'Edit hole'),
            ),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    field(
                      xController,
                      _tr('المسافة عن اليسار', 'Distance depuis la gauche', 'Distance from left'),
                    ),
                    const SizedBox(height: 8),
                    field(
                      yController,
                      _tr('المسافة عن الأعلى', 'Distance depuis le haut', 'Distance from top'),
                    ),
                    const SizedBox(height: 8),
                    field(
                      diameterController,
                      _tr('قطر الثقب', 'Diamètre du trou', 'Hole diameter'),
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
                onPressed: () {
                  final x = _parseMillimeters(xController.text);
                  final y = _parseMillimeters(yController.text);
                  final diameter = _parseMillimeters(diameterController.text);
                  final maxDiameter = math.min(panel.widthMm, panel.heightMm);
                  final valid = x != null &&
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
                },
                child: Text(_tr('حفظ', 'Enregistrer', 'Save')),
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
    xController.dispose();
    yController.dispose();
    diameterController.dispose();
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
    if (_overallWidthMmValue != null) return _overallWidthMmValue!;
    if (_overallDrawingRect != null) return _overallDrawingRect!.width;
    if (_panels.isEmpty) return 0.0;
    final left = _panels
        .map((panel) => panel.rect.left)
        .reduce((a, b) => a < b ? a : b);
    final right = _panels
        .map((panel) => panel.rect.right)
        .reduce((a, b) => a > b ? a : b);
    return right - left;
  }

  double get _overallHeightMm {
    if (_overallHeightMmValue != null) return _overallHeightMmValue!;
    if (_overallDrawingRect != null) return _overallDrawingRect!.height;
    if (_panels.isEmpty) return 0.0;
    final top = _panels
        .map((panel) => panel.rect.top)
        .reduce((a, b) => a < b ? a : b);
    final bottom = _panels
        .map((panel) => panel.rect.bottom)
        .reduce((a, b) => a > b ? a : b);
    return bottom - top;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'ارسم مستطيل الزجاج وحدده أولاً.',
              'Dessinez et sélectionnez d’abord le rectangle du verre.',
              'Draw and select the glass rectangle first.',
            ),
          ),
        ),
      );
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
              widthMm: panelWidth,
              heightMm: selectedRect.height,
              role: 'vitrine_left',
            ),
            _GlassPanel(
              rect: Rect.fromLTWH(
                selectedRect.left + panelWidth + gap,
                selectedRect.top,
                panelWidth,
                selectedRect.height,
              ),
              widthMm: panelWidth,
              heightMm: selectedRect.height,
              role: 'vitrine_right',
            ),
          ]);
      } else {
        _panels
          ..clear()
          ..add(
            _GlassPanel(
              rect: selectedRect,
              widthMm: selectedRect.width,
              heightMm: selectedRect.height,
            ),
          );
      }
      _selectedPanelIndex = 0;
    });
  }

  double? _parseMillimeters(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  Rect _rectForMeasurement(double widthMm, double heightMm, {Rect? anchor}) {
    final availableSize = _canvasSize == Size.zero
        ? MediaQuery.sizeOf(context)
        : _canvasSize;
    final maxWidth = (availableSize.width - 64).clamp(120.0, 700.0).toDouble();
    final maxHeight = (availableSize.height - 64)
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
        .clamp(8.0, availableSize.width - width - 8.0)
        .toDouble();
    final top = (center.dy - height / 2)
        .clamp(8.0, availableSize.height - height - 8.0)
        .toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  Future<void> _editMeasurements() async {
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
      drafts = [_GlassMeasurementDraft()];
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

            TextField measurementField(
              TextEditingController controller,
              String label,
              {
                ValueChanged<String>? onChanged,
              }
            ) {
              return TextField(
                controller: controller,
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
                  'قياسات الرسم',
                  'Mesures du dessin',
                  'Drawing measurements',
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
                          _tr(
                            'عرض الباب',
                            'Largeur de la porte',
                            'Door width',
                          ),
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
                                    ),
                                    if (drafts.length > 1)
                                      Align(
                                        alignment: AlignmentDirectional
                                            .centerEnd,
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
                                        icon: const Icon(
                                          Icons.delete_outline,
                                        ),
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
                  onPressed: () {
                    final valid = drafts.every((draft) {
                      final width = _parseMillimeters(
                        draft.widthController.text,
                      );
                      final height = _parseMillimeters(
                        draft.heightController.text,
                      );
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
                    final validDoorWidth = !editOverall ||
                        (overallWidth != null &&
                            doorWidth != null &&
                            doorWidth > 0 &&
                            doorWidth < overallWidth &&
                            overallWidth -
                                    doorWidth +
                                    _fixedWidthCompensation() >
                                0);
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
                  },
                  child: Text(_tr('حفظ', 'Enregistrer', 'Save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
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
            ),
          );
        }
        _panels
          ..clear()
          ..addAll(updated);
        _selectedPanelIndex = updated.isEmpty ? null : 0;
      });
    }
    for (final draft in drafts) {
      draft.dispose();
    }
    doorWidthDraft?.dispose();
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
      'glassType': _glassType,
      'glassTypeLabel': _glassTypeLabel(_glassType),
      'glassTempered': _glassTempered,
      'edgeFinish': _edgeFinish,
      'edgeFinishLabel': _edgeFinishLabel(_edgeFinish),
      'glassThicknessMm': _glassThicknessMm,
      'overallWidthMm': _overallWidthMm,
      'overallHeightMm': _overallHeightMm,
      'widthMm': _panels.first.widthMm,
      'heightMm': _panels.first.heightMm,
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
          sablageBandWidthMm: _sablageBandWidth(),
          overallHeightMm: _overallHeightMm,
          sablageMode: _sablageMode,
          workTypeLabel: _workTypeLabel(_workType),
        ),
      ),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  Future<void> _showWorkTypeSheet() async {
    int selectedTab = 0;
    const tabTypes = [
      [
        GlassWorkType.showerCabin,
        GlassWorkType.slidingShowerCabin,
        GlassWorkType.singleDoorShowerCabin,
        GlassWorkType.vitrineSingleDoor,
        GlassWorkType.vitrineDoubleDoor,
      ],
      [
        GlassWorkType.showerCabin,
        GlassWorkType.slidingShowerCabin,
        GlassWorkType.singleDoorShowerCabin,
      ],
      [GlassWorkType.vitrineSingleDoor, GlassWorkType.vitrineDoubleDoor],
    ];
    final tabLabels = [
      _tr('عام', 'Général', 'Common'),
      _tr('كابين دوش', 'Cabine de douche', 'Shower cabin'),
      _tr('فيترين', 'Vitrine', 'Storefront'),
    ];
    final tabIcons = [Icons.tune, Icons.shower, Icons.storefront];

    final selected = await showModalBottomSheet<GlassWorkType>(
      context: context,
      showDragHandle: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _tr('إغلاق القائمة', 'Fermer le menu', 'Close menu'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0; index < tabLabels.length; index++)
                        _glassCategoryTab(
                          label: tabLabels[index],
                          icon: tabIcons[index],
                          selected: selectedTab == index,
                          onPressed: () =>
                              setSheetState(() => selectedTab = index),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: _suggestTypeButtons(
                    tabTypes[selectedTab],
                    (type) => Navigator.pop(context, type),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) _applySelectedWorkType(selected);
  }

  Widget _glassCategoryTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final color = selected ? Colors.blue : Colors.blueGrey.shade700;
    return InkWell(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? Colors.blue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _workTypeIcon(GlassWorkType type) {
    return switch (type) {
      GlassWorkType.showerCabin => Icons.shower,
      GlassWorkType.slidingShowerCabin => Icons.compare_arrows,
      GlassWorkType.singleDoorShowerCabin => Icons.door_front_door_outlined,
      GlassWorkType.vitrineSingleDoor => Icons.storefront,
      GlassWorkType.vitrineDoubleDoor => Icons.meeting_room_outlined,
    };
  }

  Widget _suggestTypeButtons(
    List<GlassWorkType> types,
    ValueChanged<GlassWorkType> onSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in types)
            OutlinedButton.icon(
              onPressed: () => onSelected(type),
              icon: Icon(_workTypeIcon(type), size: 18),
              label: Text(_workTypeLabel(type)),
              style: OutlinedButton.styleFrom(
                foregroundColor: type == _workType
                    ? Colors.blue.shade800
                    : null,
                backgroundColor: type == _workType
                    ? Colors.blue.withValues(alpha: 0.10)
                    : null,
                side: BorderSide(
                  color: type == _workType
                      ? Colors.blue
                      : Colors.blueGrey.shade200,
                  width: type == _workType ? 2 : 1,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSablageSheet() async {
    final selected = await showModalBottomSheet<_SablageMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _tr('نوع التعتيم', 'Type de sablage', 'Sablage type'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, _SablageMode.full),
                icon: const Icon(Icons.format_color_fill),
                label: Text(
                  _tr('تعتيم كامل', 'Sablage complet', 'Full frosting'),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _SablageMode.decorative),
                icon: const Icon(Icons.view_agenda_outlined),
                label: Text(
                  _tr(
                    'تعتيم ديكور',
                    'Sablage décoratif',
                    'Decorative frosting',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    _pushHistory();
    if (selected == _SablageMode.full) {
      setState(() {
        _sablageMode = selected;
        _sablageBands.clear();
      });
    } else {
      setState(() => _sablageMode = selected);
      await _editSablageOptions();
    }
  }

  void _regenerateSablageBands() {
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
    final offsets = <double>[];
    if (_sablageRangeMode) {
      final rangeStart = _sablageFromBottom ? height - end : start;
      final rangeEnd = _sablageFromBottom ? height - start : end;
      for (
        var offset = rangeStart;
        offset + opaqueWidth <= rangeEnd + 0.1;
        offset += pitch
      ) {
        offsets.add(offset);
      }
    } else {
      final count = int.tryParse(_sablageCountController.text.trim()) ?? 0;
      for (var index = 0; index < count; index++) {
        final offset = _sablageFromBottom
            ? height - start - opaqueWidth - index * pitch
            : start + index * pitch;
        if (offset >= 0 && offset + opaqueWidth <= height + 0.1) {
          offsets.add(offset);
        }
      }
    }
    _sablageBands
      ..clear()
      ..addAll(
        offsets.map(
          (offset) => _SablageBand(offsetMm: offset, widthMm: opaqueWidth),
        ),
      );
  }

  Future<void> _editSablageOptions() async {
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            _tr(
              'إعداد تعتيم الديكور',
              'Réglage du sablage décoratif',
              'Decorative frosting settings',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _sablageBandWidthController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'عرض الباندة المعتمة',
                      'Largeur de la bande opaque',
                      'Opaque band width',
                    ),
                    suffixText: 'mm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sablageTransparentWidthController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'عرض الباندة الشفافة',
                      'Largeur de la bande transparente',
                      'Transparent band width',
                    ),
                    suffixText: 'mm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                RadioListTile<bool>(
                  value: false,
                  groupValue: _sablageRangeMode,
                  onChanged: (value) =>
                      setDialogState(() => _sablageRangeMode = value ?? false),
                  title: Text(
                    _tr('عدد الباندات', 'Nombre de bandes', 'Number of bands'),
                  ),
                ),
                if (!_sablageRangeMode)
                  TextField(
                    controller: _sablageCountController,
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
                    _tr('نطاق القياس', 'Plage de mesure', 'Measurement range'),
                  ),
                ),
                TextField(
                  controller: _sablageStartController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'البداية من الصفر',
                      'Début depuis zéro',
                      'Start from zero',
                    ),
                    suffixText: 'mm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_sablageRangeMode) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sablageEndController,
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
                SwitchListTile(
                  value: _sablageFromBottom,
                  onChanged: (value) =>
                      setDialogState(() => _sablageFromBottom = value),
                  title: Text(
                    _tr(
                      'القياس من الأسفل',
                      'Mesurer depuis le bas',
                      'Measure from bottom',
                    ),
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
              onPressed: () {
                final opaque = _parseMillimeters(
                  _sablageBandWidthController.text,
                );
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
              },
              child: Text(_tr('حفظ', 'Enregistrer', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(_regenerateSablageBands);
    }
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

  Future<void> _showEdgeFinishSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop_square),
              title: Text(
                _tr('حواف حادة', 'Bords vifs', 'Sharp edges'),
              ),
              trailing: _edgeFinish == 'sharp'
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(sheetContext, 'sharp'),
            ),
            ListTile(
              leading: const Icon(Icons.rounded_corner),
              title: Text(
                _tr('حواف ناعمة', 'Bords adoucis', 'Smooth edges'),
              ),
              trailing: _edgeFinish == 'smooth'
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(sheetContext, 'smooth'),
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
                  _tr('خيارات نظام الزجاج', 'Système de vitrage', 'Glass system'),
                ),
                onTap: () => open(_showWorkTypeSheet),
              ),
              ListTile(
                leading: const Icon(Icons.rounded_corner),
                title: Text(
                  _tr('نوع الحواف', 'Type de chants', 'Edge type'),
                ),
                onTap: () => open(_showEdgeFinishSheet),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawingToolbar() {
    if (_isCompactLayout(context)) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _editMeasurements,
          icon: const Icon(Icons.straighten),
          label: Text(_measurementSummary()),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: _editMeasurements,
            icon: const Icon(Icons.straighten),
            label: Text(_measurementSummary()),
          ),
          if (_isSlidingStraight) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _toggleSlidingSides,
              icon: const Icon(Icons.swap_horiz),
              label: Text(
                _tr(
                  'قلب الباب والثابت',
                  'Inverser la porte et le fixe',
                  'Swap door and fixed panel',
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _editHandleFromToolbar,
            icon: const Icon(Icons.pan_tool_outlined),
            label: Text(_tr('مقبض 200 مم', 'Poignée 200 mm', '200 mm handle')),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 142,
            child: DropdownButtonFormField<double>(
              value: _glassThicknessMm,
              isDense: true,
              decoration: InputDecoration(
                labelText: _tr(
                  'سمك الزجاج',
                  'Épaisseur du verre',
                  'Glass thickness',
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: const OutlineInputBorder(),
              ),
              items: const [10.0, 8.0, 6.0, 5.0, 4.0]
                  .map(
                    (thickness) => DropdownMenuItem<double>(
                      value: thickness,
                      child: Text('${thickness.toStringAsFixed(0)} mm'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null || value == _glassThicknessMm) return;
                _pushHistory();
                setState(() => _glassThicknessMm = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              value: _glassType,
              isDense: true,
              decoration: InputDecoration(
                labelText: _tr('نوع الزجاج', 'Type de verre', 'Glass type'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: const OutlineInputBorder(),
              ),
              items: const ['شفاف', 'ملون', 'عاكس', 'مصفح', 'معتّم']
                  .map(
                    (type) => DropdownMenuItem<String>(
                      value: type,
                      child: Text(type),
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
          FilterChip(
            selected: _glassTempered,
            label: Text(
              _tr('مقسّى', 'Trempé', 'Tempered'),
              style: TextStyle(
                color: _glassTempered ? Colors.white : null,
              ),
            ),
            selectedColor: Colors.cyan.shade700,
            onSelected: (value) => setState(() => _glassTempered = value),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              value: _edgeFinish,
              isDense: true,
              decoration: InputDecoration(
                labelText: _tr(
                  'نوع الحواف',
                  'Type de chants',
                  'Edge type',
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: const OutlineInputBorder(),
              ),
              items: const ['sharp', 'smooth']
                  .map(
                    (finish) => DropdownMenuItem<String>(
                      value: finish,
                      child: Text(_edgeFinishLabel(finish)),
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
          OutlinedButton.icon(
            onPressed: _showSablageSheet,
            icon: Icon(
              _sablageMode == _SablageMode.full
                  ? Icons.format_color_fill
                  : Icons.brush_outlined,
            ),
            label: Text(switch (_sablageMode) {
              _SablageMode.full => _tr(
                'تعتيم كامل',
                'Sablage complet',
                'Full frosting',
              ),
              _SablageMode.decorative => _tr(
                'تعتيم ديكور',
                'Sablage décoratif',
                'Decorative frosting',
              ),
              _SablageMode.none => _tr('الصابلاج', 'Sablage', 'Frosting'),
            }),
          ),
          if (_sablageBands.isNotEmpty)
            IconButton(
              tooltip: _tr(
                'مسح الصابلاج',
                'Effacer le sablage',
                'Clear sablage',
              ),
              onPressed: () {
                _pushHistory();
                setState(_sablageBands.clear);
              },
              icon: const Icon(Icons.clear_all),
            ),
          const VerticalDivider(width: 12),
          IconButton(
            tooltip: _tr('تصغير', 'Zoom arrière', 'Zoom out'),
            onPressed: () => _changeZoom(-0.1),
            icon: const Icon(Icons.zoom_out),
          ),
          Text('${(_zoom * 100).round()}%'),
          IconButton(
            tooltip: _tr('تكبير', 'Zoom avant', 'Zoom in'),
            onPressed: () => _changeZoom(0.1),
            icon: const Icon(Icons.zoom_in),
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
      appBar: AppBar(
        title: Text(_tr('رسم الزجاج', 'Dessin du verre', 'Glass drawing')),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildDrawingToolbar(),
              if (_isSlidingStraight) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
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
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: _tr(
                            'عرض الباب',
                            'Largeur de la porte',
                            'Door width',
                          ),
                          suffixText: 'mm',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
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
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _handleCanvasTap,
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
                            draftSablageOffsetMm: _draftSablageOffsetMm,
                            sablageBandWidthMm: _sablageBandWidth(),
                            overallHeightMm: _overallHeightMm,
                            sablageMode: _sablageMode,
                            zoom: _zoom,
                            selectedPanelIndex: _selectedPanelIndex,
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
              if (_selectedPanelIndex != null && !compact) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showWorkTypeSheet,
                    icon: const Icon(Icons.dashboard_customize_outlined),
                    label: Text(
                      _tr(
                        'خيارات نظام الزجاج للمستطيل المحدد',
                        'Options du système pour le rectangle sélectionné',
                        'Glass system options for the selected rectangle',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _showManufacturingSheet,
                  icon: const Icon(Icons.description_outlined),
                  label: Text(
                    _tr(
                      'عرض ورقة التصنيع',
                      'Afficher la fiche de fabrication',
                      'Show manufacturing sheet',
                    ),
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
    required this.sablageBandWidthMm,
    required this.overallHeightMm,
    required this.sablageMode,
    required this.workTypeLabel,
  });

  final Map<String, dynamic> payload;
  final List<_GlassPanel> panels;
  final Size drawingCanvasSize;
  final List<_SablageBand> sablageBands;
  final double sablageBandWidthMm;
  final double overallHeightMm;
  final _SablageMode sablageMode;
  final String workTypeLabel;

  String _value(Object? value, [String fallback = '—']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _mm(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) return '—';
    return '${number.toStringAsFixed(0)} mm';
  }

  String _role(String role) {
    switch (role) {
      case 'door':
        return 'باب';
      case 'fixed':
        return 'ثابت';
      default:
        return 'لوح زجاج';
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

  Widget _panelDetails(_GlassPanel panel, int index) {
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
                  '${_role(panel.role)} — ${_mm(panel.widthMm)} × ${_mm(panel.heightMm)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  panel.holes.isEmpty ? 'بدون ثقوب' : 'الثقوب: $holes',
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
    final maxCanvasHeight = math.max(
      drawingCanvasSize.height,
      300.0,
    ).toDouble();
    final isFrosted = sablageMode != _SablageMode.none;
    final tempered = payload['glassTempered'] == true ? 'نعم' : 'لا';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ورقة تصنيع الزجاج'),
        backgroundColor: Colors.cyan.shade800,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, payload),
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text(
              'اعتماد',
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
                    'طلب تصنيع الزجاج',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${panels.length} قطعة',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              workTypeLabel,
              style: const TextStyle(color: Colors.blueGrey),
            ),
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
                        draftSablageOffsetMm: null,
                        sablageBandWidthMm: sablageBandWidthMm,
                        overallHeightMm: overallHeightMm,
                        sablageMode: sablageMode,
                        zoom: 1.0,
                        selectedPanelIndex: null,
                        color: Colors.cyan.shade800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'مواصفات الزجاج',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _spec('نوع الزجاج', _value(payload['glassType'])),
                _spec('السمك', _mm(payload['glassThicknessMm'])),
              ],
            ),
            Row(
              children: [
                _spec('مقسّى', tempered),
                _spec(
                  'نوع الحواف',
                  _value(payload['edgeFinishLabel'] ?? payload['edgeFinish']),
                ),
              ],
            ),
            Row(
              children: [
                _spec('العرض الإجمالي', _mm(payload['overallWidthMm'])),
                _spec('الارتفاع الإجمالي', _mm(payload['overallHeightMm'])),
              ],
            ),
            if (isFrosted)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  sablageMode == _SablageMode.full
                      ? 'الصابلاج: تعتيم كامل'
                      : 'الصابلاج: ${sablageBands.length} باندات، عرض الباندة ${_mm(sablageBandWidthMm)}',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
              ),
            const SizedBox(height: 6),
            const Text(
              'تفاصيل القطع والثقوب',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < panels.length; index++)
              _panelDetails(panels[index], index),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, payload),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('اعتماد وإضافة إلى الطلب'),
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
    required this.draftSablageOffsetMm,
    required this.sablageBandWidthMm,
    required this.overallHeightMm,
    required this.sablageMode,
    required this.zoom,
    required this.selectedPanelIndex,
    required this.color,
  });

  final List<_GlassPanel> panels;
  final Rect? draftPanel;
  final double? draftWidthMm;
  final double? draftHeightMm;
  final List<_SablageBand> sablageBands;
  final double? draftSablageOffsetMm;
  final double sablageBandWidthMm;
  final double overallHeightMm;
  final _SablageMode sablageMode;
  final double zoom;
  final int? selectedPanelIndex;
  final Color color;

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
      _paintPanel(
        canvas,
        panel.rect,
        panel.widthMm,
        panel.heightMm,
        glassPaint,
        glassBorderPaint,
        reflectionPaint,
        verticalDimensionOnLeft:
            panel.role == 'door' &&
            panels.any(
              (other) =>
                  other.role == 'fixed' &&
                  panel.rect.center.dx < other.rect.center.dx,
            ),
      );
    }
    if (draftPanel != null) {
      _paintPanel(
        canvas,
        draftPanel!,
        draftWidthMm ?? draftPanel!.width,
        draftHeightMm ?? draftPanel!.height,
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
    }
    canvas.restore();
  }

  double _safeHoleDiameterMm(_GlassPanel panel, _GlassHole hole) {
    final maxDiameter = math.min(panel.widthMm, panel.heightMm);
    return hole.diameterMm.clamp(0.0, maxDiameter).toDouble();
  }

  double _safeHoleXMm(
    _GlassPanel panel,
    _GlassHole hole,
    double diameterMm,
  ) {
    final minimum = diameterMm / 2;
    final maximum = math.max(minimum, panel.widthMm - minimum);
    return hole.xMm.clamp(minimum, maximum).toDouble();
  }

  double _safeHoleYMm(
    _GlassPanel panel,
    _GlassHole hole,
    double diameterMm,
  ) {
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
    final labelBackgroundPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.94)
      ..style = PaintingStyle.fill;
    final textStyle = const TextStyle(
      fontSize: 9,
      color: Colors.black,
      fontWeight: FontWeight.w600,
    );

    void drawLabel(String value, Offset position) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelRect = Rect.fromCenter(
        center: position,
        width: painter.width + 8,
        height: painter.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        labelBackgroundPaint,
      );
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }

    void drawArrowDimension(Offset from, Offset to, String label) {
      if ((to - from).distance < 8) return;
      canvas.drawLine(from, to, dimensionPaint);
      const arrowSize = 5.5;
      final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
      void drawHead(Offset point, double direction) {
        final first = Offset(
          point.dx + arrowSize * math.cos(direction + math.pi - math.pi / 6),
          point.dy + arrowSize * math.sin(direction + math.pi - math.pi / 6),
        );
        final second = Offset(
          point.dx + arrowSize * math.cos(direction + math.pi + math.pi / 6),
          point.dy + arrowSize * math.sin(direction + math.pi + math.pi / 6),
        );
        canvas
          ..drawLine(point, first, dimensionPaint)
          ..drawLine(point, second, dimensionPaint);
      }

      drawHead(from, angle);
      drawHead(to, angle + math.pi);
      final middle = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      final labelOffset = (to.dx - from.dx).abs() >= (to.dy - from.dy).abs()
          ? const Offset(0, -11)
          : const Offset(13, 0);
      drawLabel(label, middle + labelOffset);
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

    double holeRadius(_GlassHole hole) => math.max(
      3.0,
      holeDiameter(hole) * math.min(scaleX, scaleY) / 2,
    );

    for (var index = 0; index < panel.holes.length; index++) {
      final hole = panel.holes[index];
      final center = holeCenter(hole);
      final radius = holeRadius(hole);
      final diameterMm = holeDiameter(hole);
      final xMm = holeX(hole);
      final yMm = holeY(hole);
      final leftMm = (xMm - diameterMm / 2).clamp(0.0, panel.widthMm);
      final rightMm = (panel.widthMm - xMm - diameterMm / 2)
          .clamp(0.0, panel.widthMm);
      final sharedTop = _sharedSlidingTop();
      final measurementTop =
          sharedTop != null && panel.role == 'door'
              ? sharedTop
              : panel.rect.top;
      final measurementHeightMm =
          sharedTop != null && panel.role == 'door'
              ? overallHeightMm
              : panel.heightMm;
      final topAllowanceMm = (measurementTop - panel.rect.top) / scaleY;
      final alignedYMm = yMm - topAllowanceMm;
      final topMm = (alignedYMm - diameterMm / 2)
          .clamp(0.0, measurementHeightMm);
      final bottomMm = (measurementHeightMm - alignedYMm - diameterMm / 2)
          .clamp(0.0, measurementHeightMm);

      // Direct edge-to-edge dimensions. There are no projection lines or
      // remote annotation lanes: each arrow starts at the glass edge and
      // stops exactly at the nearest edge of the hole.
      final fromLeft = leftMm <= rightMm;
      final holeEdgeX = fromLeft ? center.dx - radius : center.dx + radius;
      final glassEdgeX = fromLeft ? panel.rect.left : panel.rect.right;
      drawArrowDimension(
        Offset(glassEdgeX, center.dy),
        Offset(holeEdgeX, center.dy),
        '${(fromLeft ? leftMm : rightMm).toStringAsFixed(0)} mm',
      );

      final fromTop = topMm <= bottomMm;
      final holeEdgeY = fromTop ? center.dy - radius : center.dy + radius;
      final glassEdgeY = fromTop ? measurementTop : panel.rect.bottom;
      drawArrowDimension(
        Offset(center.dx, glassEdgeY),
        Offset(center.dx, holeEdgeY),
        '${(fromTop ? topMm : bottomMm).toStringAsFixed(0)} mm',
      );

      drawLabel(
        '#${index + 1} Ø ${diameterMm.toStringAsFixed(0)} mm',
        center + const Offset(0, 14),
      );
    }

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
    for (final entry in groupedHoles.entries) {
      if (entry.value.length != 2) continue;
      final first = holeCenter(entry.value[0]);
      final second = holeCenter(entry.value[1]);
      final isHorizontal =
          (second.dx - first.dx).abs() >= (second.dy - first.dy).abs();
      final distanceMm = isHorizontal
          ? ((holeX(entry.value[1]) - holeX(entry.value[0])).abs() -
                  (holeDiameter(entry.value[0]) +
                          holeDiameter(entry.value[1])) /
                      2)
              .clamp(0.0, double.infinity)
          : ((holeY(entry.value[1]) - holeY(entry.value[0])).abs() -
                  (holeDiameter(entry.value[0]) +
                          holeDiameter(entry.value[1])) /
                      2)
              .clamp(0.0, double.infinity);
      if (isHorizontal) {
        final leftHole = entry.value[0].xMm <= entry.value[1].xMm
            ? entry.value[0]
            : entry.value[1];
        final rightHole = identical(leftHole, entry.value[0])
            ? entry.value[1]
            : entry.value[0];
        final leftEdge = holeCenter(leftHole).dx + holeRadius(leftHole);
        final rightEdge = holeCenter(rightHole).dx - holeRadius(rightHole);
        drawArrowDimension(
          Offset(leftEdge, holeCenter(leftHole).dy),
          Offset(rightEdge, holeCenter(rightHole).dy),
          '${distanceMm.toStringAsFixed(0)} mm',
        );
      } else {
        final topHole = entry.value[0].yMm <= entry.value[1].yMm
            ? entry.value[0]
            : entry.value[1];
        final bottomHole = identical(topHole, entry.value[0])
            ? entry.value[1]
            : entry.value[0];
        final topEdge = holeCenter(topHole).dy + holeRadius(topHole);
        final bottomEdge = holeCenter(bottomHole).dy - holeRadius(bottomHole);
        drawArrowDimension(
          Offset(holeCenter(topHole).dx, topEdge),
          Offset(holeCenter(bottomHole).dx, bottomEdge),
          '${distanceMm.toStringAsFixed(0)} mm',
        );
      }
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

  void _paintPanel(
    Canvas canvas,
    Rect panel,
    double widthMm,
    double heightMm,
    Paint glassPaint,
    Paint glassBorderPaint,
    Paint reflectionPaint, {
    bool verticalDimensionOnLeft = false,
  }) {
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

    final dimensionPaint = Paint()
      ..color = Colors.blueGrey.shade700
      ..strokeWidth = 1;
    _drawDimension(
      canvas,
      start: Offset(panel.left, panel.top - 18),
      end: Offset(panel.right, panel.top - 18),
      label: '${widthMm.toStringAsFixed(0)} mm',
      horizontal: true,
      paint: dimensionPaint,
    );
    final verticalDimensionX = verticalDimensionOnLeft
        ? panel.left - 18
        : panel.right + 18;
    _drawDimension(
      canvas,
      start: Offset(verticalDimensionX, panel.top),
      end: Offset(verticalDimensionX, panel.bottom),
      label: '${heightMm.toStringAsFixed(0)} mm',
      horizontal: false,
      paint: dimensionPaint,
    );
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
        style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    if (horizontal) {
      text.paint(canvas, midpoint - Offset(text.width / 2, text.height + 3));
    } else {
      canvas.save();
      canvas.translate(
        midpoint.dx + text.height + 4,
        midpoint.dy + text.width / 2,
      );
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

  _HoleOverride copy() => _HoleOverride(
    xMm: xMm,
    yMm: yMm,
    diameterMm: diameterMm,
  );
}

class _SablageBand {
  const _SablageBand({required this.offsetMm, required this.widthMm});

  final double offsetMm;
  final double widthMm;
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
    required this.holeDiameterMm,
    required this.holeOverrides,
    required this.sablageMode,
    required this.sablageRangeMode,
    required this.sablageFromBottom,
    required this.glassThicknessMm,
    required this.doorOnLeft,
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
    required double holeDiameterMm,
    required Map<String, _HoleOverride> holeOverrides,
    required _SablageMode sablageMode,
    required bool sablageRangeMode,
    required bool sablageFromBottom,
    required double glassThicknessMm,
    required bool doorOnLeft,
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
      holeDiameterMm: holeDiameterMm,
      holeOverrides: holeOverrides.map(
        (key, value) => MapEntry(key, value.copy()),
      ),
      sablageMode: sablageMode,
      sablageRangeMode: sablageRangeMode,
      sablageFromBottom: sablageFromBottom,
      glassThicknessMm: glassThicknessMm,
      doorOnLeft: doorOnLeft,
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
  final double holeDiameterMm;
  final Map<String, _HoleOverride> holeOverrides;
  final _SablageMode sablageMode;
  final bool sablageRangeMode;
  final bool sablageFromBottom;
  final double glassThicknessMm;
  final bool doorOnLeft;
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
