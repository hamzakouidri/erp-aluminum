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
  static const _doorTopHoleSideOffsetMm = 80.0;
  static const _doorTopHoleTopOffsetMm = 35.0;
  static const _handleHoleEdgeOffsetMm = 50.0;
  static const _handleHoleSpacingMm = 200.0;
  static const _towelHoleSpacingMm = 400.0;

  GlassWorkType _workType = GlassWorkType.vitrineSingleDoor;
  final List<_GlassPanel> _panels = [];
  int? _selectedPanelIndex;
  final _doorWidthController = TextEditingController(text: '800');
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
  bool _doorOnLeft = true;

  bool get _isSlidingStraight => _workType == GlassWorkType.slidingShowerCabin;

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
    _pushHistory();
    setState(() {
      if (_isSlidingStraight) {
        _overallDrawingRect = panel;
        _overallWidthMmValue = panel.width;
        _overallHeightMmValue = panel.height;
        _applySlidingLayout();
      } else {
        _panels.add(
          _GlassPanel(
            rect: panel,
            widthMm: panel.width,
            heightMm: panel.height,
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
        if ((holePosition - position).distance <= 28) {
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
    final isHandle = target.purpose.startsWith('handle_');
    final isTowel = target.purpose.startsWith('towel_');
    if (!isHandle && !isTowel) return;

    setState(() {
      if (isHandle) {
        _handleEdgeOffsetMm = (_handleEdgeOffsetMm + dxMm)
            .clamp(0.0, math.max(0.0, panel.widthMm - _holeDiameterMm))
            .toDouble();
        _handleCenterFromTopMm =
            ((_handleCenterFromTopMm ?? panel.heightMm / 2) + dyMm)
                .clamp(
                  _handleSpacingMm / 2,
                  math.max(
                    _handleSpacingMm / 2,
                    panel.heightMm - _handleSpacingMm / 2,
                  ),
                )
                .toDouble();
      } else {
        _towelCenterFromLeftMm =
            ((_towelCenterFromLeftMm ?? panel.widthMm / 2) + dxMm)
                .clamp(0.0, panel.widthMm)
                .toDouble();
        _towelCenterFromTopMm =
            ((_towelCenterFromTopMm ?? panel.heightMm / 2) + dyMm)
                .clamp(
                  _towelSpacingMm / 2,
                  math.max(
                    _towelSpacingMm / 2,
                    panel.heightMm - _towelSpacingMm / 2,
                  ),
                )
                .toDouble();
      }
      _applySlidingLayout();
    });
  }

  void _handleCanvasTap(TapUpDetails details) {
    final target = _findMovableHole(_canvasPosition(details.localPosition));
    if (target != null) {
      _editMovableHole(target.purpose);
      return;
    }
    final position = _canvasPosition(details.localPosition);
    final panelIndex = _panels.lastIndexWhere(
      (panel) => panel.rect.contains(position),
    );
    setState(() => _selectedPanelIndex = panelIndex < 0 ? null : panelIndex);
  }

  bool get _sablageEnabled => _sablageMode == _SablageMode.decorative;

  double _number(TextEditingController controller, double fallback) =>
      _parseMillimeters(controller.text) ?? fallback;

  double _workshopCompensation() => _defaultDoorHeightIncreaseMm;

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
    final practicalWidth = drawnWidthMm + _workshopCompensation();
    final doorWidth = _doorWidth();
    final fixedWidth = practicalWidth - doorWidth;
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
    // The separation is visual only and intentionally fixed at two pixels.
    const gap = 2.0;
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
          holes: _doorHoles(doorWidth, doorHeightMm),
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

  List<_GlassHole> _doorHoles(double widthMm, double heightMm) {
    final middleY = (_handleCenterFromTopMm ?? heightMm / 2)
        .clamp(
          _handleSpacingMm / 2,
          math.max(_handleSpacingMm / 2, heightMm - _handleSpacingMm / 2),
        )
        .toDouble();
    return [
      _GlassHole(
        xMm: _doorTopHoleSideOffsetMm,
        yMm: _doorTopHoleTopOffsetMm,
        diameterMm: _holeDiameterMm,
        purpose: 'door_top_left',
      ),
      _GlassHole(
        xMm: widthMm - _doorTopHoleSideOffsetMm,
        yMm: _doorTopHoleTopOffsetMm,
        diameterMm: _holeDiameterMm,
        purpose: 'door_top_right',
      ),
      _GlassHole(
        xMm: _handleEdgeOffsetMm,
        yMm: middleY - _handleSpacingMm / 2,
        diameterMm: _holeDiameterMm,
        purpose: 'handle_top',
      ),
      _GlassHole(
        xMm: _handleEdgeOffsetMm,
        yMm: middleY + _handleSpacingMm / 2,
        diameterMm: _holeDiameterMm,
        purpose: 'handle_bottom',
      ),
    ];
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
    return [
      _GlassHole(
        xMm: middleX - _towelSpacingMm / 2,
        yMm: middleY,
        diameterMm: _holeDiameterMm,
        purpose: 'towel_left',
      ),
      _GlassHole(
        xMm: middleX + _towelSpacingMm / 2,
        yMm: middleY,
        diameterMm: _holeDiameterMm,
        purpose: 'towel_right',
      ),
    ];
  }

  Future<void> _editMovableHole(String purpose) async {
    final isHandle = purpose.startsWith('handle_');
    final edgeController = TextEditingController(
      text:
          (isHandle
                  ? _handleEdgeOffsetMm
                  : (_towelCenterFromLeftMm ?? _overallWidthMm / 2))
              .toStringAsFixed(0),
    );
    final centerController = TextEditingController(
      text:
          (isHandle
                  ? (_handleCenterFromTopMm ?? _overallHeightMm / 2)
                  : (_towelCenterFromTopMm ?? _overallHeightMm / 2))
              .toStringAsFixed(0),
    );
    final spacingController = TextEditingController(
      text: (isHandle ? _handleSpacingMm : _towelSpacingMm).toStringAsFixed(0),
    );
    final diameterController = TextEditingController(
      text: _holeDiameterMm.toStringAsFixed(0),
    );
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            _tr(
              isHandle ? 'مقابض الباب' : 'علاقة المنشفة',
              isHandle ? 'Poignée de porte' : 'Porte-serviettes',
              isHandle ? 'Door handle' : 'Towel hanger',
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: edgeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      isHandle ? 'البعد عن الحافة' : 'البعد عن اليسار',
                      isHandle
                          ? 'Distance du bord'
                          : 'Distance depuis la gauche',
                      isHandle ? 'Distance from edge' : 'Distance from left',
                    ),
                    suffixText: 'mm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: centerController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'بعد المركز عن الأعلى',
                      'Centre depuis le haut',
                      'Center from top',
                    ),
                    suffixText: 'mm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: spacingController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'المسافة بين الثقبين',
                      'Distance entre les trous',
                      'Distance between holes',
                    ),
                    suffixText: 'mm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: diameterController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'قطر الثقب',
                      'Diamètre du trou',
                      'Hole diameter',
                    ),
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
              onPressed: () {
                final edge = _parseMillimeters(edgeController.text);
                final center = _parseMillimeters(centerController.text);
                final spacing = _parseMillimeters(spacingController.text);
                final diameter = _parseMillimeters(diameterController.text);
                if (edge == null ||
                    center == null ||
                    spacing == null ||
                    diameter == null ||
                    edge < 0 ||
                    center < 0 ||
                    spacing <= 0 ||
                    diameter <= 0) {
                  setDialogState(
                    () => error = _tr(
                      'أدخل أرقامًا صحيحة.',
                      'Saisissez des valeurs valides.',
                      'Enter valid values.',
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
      final edge = _parseMillimeters(edgeController.text)!;
      final center = _parseMillimeters(centerController.text)!;
      final spacing = _parseMillimeters(spacingController.text)!;
      final diameter = _parseMillimeters(diameterController.text)!;
      _pushHistory();
      setState(() {
        _holeDiameterMm = diameter;
        if (isHandle) {
          _handleEdgeOffsetMm = edge;
          _handleCenterFromTopMm = center;
          _handleSpacingMm = spacing;
        } else {
          _towelCenterFromLeftMm = edge;
          _towelCenterFromTopMm = center;
          _towelSpacingMm = spacing;
        }
        _applySlidingLayout();
      });
    }
    edgeController.dispose();
    centerController.dispose();
    spacingController.dispose();
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
    await _editMovableHole('handle_top');
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
      final practicalWidth = selectedPanel.widthMm + _workshopCompensation();
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
            return AlertDialog(
              title: Text(
                _tr(
                  'قياسات الرسم',
                  'Mesures du dessin',
                  'Drawing measurements',
                ),
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < drafts.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: drafts[index].widthController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: _tr(
                                      'العرض ${index + 1}',
                                      'Largeur ${index + 1}',
                                      'Width ${index + 1}',
                                    ),
                                    suffixText: 'mm',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: drafts[index].heightController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: _tr(
                                      'الطول ${index + 1}',
                                      'Hauteur ${index + 1}',
                                      'Height ${index + 1}',
                                    ),
                                    suffixText: 'mm',
                                    border: const OutlineInputBorder(),
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
                    if (!valid || drafts.isEmpty) {
                      setDialogState(
                        () => error = _tr(
                          'أدخل قياسات صحيحة لكل القطع.',
                          'Saisissez des mesures valides pour chaque panneau.',
                          'Enter valid measurements for every panel.',
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
  }

  void _calculateQuantityAndCost() {
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

    final area = _panels.fold<double>(
      0,
      (sum, panel) => sum + (panel.widthMm / 1000) * (panel.heightMm / 1000),
    );

    Navigator.pop(context, <String, dynamic>{
      'type': 'tempered_glass_work',
      'workType': _workType.name,
      'workTypeLabel': _workTypeLabel(_workType),
      'glassThicknessMm': _glassThicknessMm,
      'overallWidthMm': _overallWidthMm,
      'overallHeightMm': _overallHeightMm,
      'widthMm': _panels.first.widthMm,
      'heightMm': _panels.first.heightMm,
      'drawingVersion': 1,
      'slidingRule': _isSlidingStraight
          ? {
              'drawnWidthMm': _overallWidthMm,
              'practicalWidthMm': _overallWidthMm + _workshopCompensation(),
              'doorWidthMm': _doorWidth(),
              'fixedWidthMm':
                  _overallWidthMm + _workshopCompensation() - _doorWidth(),
              'workshopCompensationMm': _workshopCompensation(),
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
    });
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

  Widget _buildDrawingToolbar() {
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
          const VerticalDivider(width: 12),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('رسم الزجاج', 'Dessin du verre', 'Glass drawing')),
        backgroundColor: Colors.cyan.shade800,
        foregroundColor: Colors.white,
      ),
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
                            sablageBands: _sablageBands,
                            draftSablageOffsetMm: _draftSablageOffsetMm,
                            sablageBandWidthMm: _sablageBandWidth(),
                            overallHeightMm: _overallHeightMm,
                            sablageMode: _sablageMode,
                            zoom: _zoom,
                            selectedPanelIndex: _selectedPanelIndex,
                            centerLabel: _tr('مركز', 'Centre', 'Center'),
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
              if (_selectedPanelIndex != null) ...[
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
                  onPressed: _calculateQuantityAndCost,
                  icon: const Icon(Icons.calculate_outlined),
                  label: Text(
                    _tr(
                      'حساب الكمية والتكلفة',
                      'Calculer quantité et coût',
                      'Calculate quantity and cost',
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

class _GlassPanelDrawingPainter extends CustomPainter {
  const _GlassPanelDrawingPainter({
    required this.panels,
    required this.draftPanel,
    required this.sablageBands,
    required this.draftSablageOffsetMm,
    required this.sablageBandWidthMm,
    required this.overallHeightMm,
    required this.sablageMode,
    required this.zoom,
    required this.selectedPanelIndex,
    required this.centerLabel,
    required this.color,
  });

  final List<_GlassPanel> panels;
  final Rect? draftPanel;
  final List<_SablageBand> sablageBands;
  final double? draftSablageOffsetMm;
  final double sablageBandWidthMm;
  final double overallHeightMm;
  final _SablageMode sablageMode;
  final double zoom;
  final int? selectedPanelIndex;
  final String centerLabel;
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
      ..strokeWidth = 2;
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
        draftPanel!.width,
        draftPanel!.height,
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
      _paintHoleDimensions(canvas, panel, size);
    }
    if (selectedPanelIndex != null &&
        selectedPanelIndex! >= 0 &&
        selectedPanelIndex! < panels.length) {
      final selectionPaint = Paint()
        ..color = Colors.deepOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
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
    for (final hole in panel.holes) {
      final center = Offset(
        panel.rect.left + hole.xMm * scaleX,
        panel.rect.top + hole.yMm * scaleY,
      );
      final radius = math
          .max(3.0, hole.diameterMm * math.min(scaleX, scaleY) / 2)
          .toDouble();
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, border);
    }
  }

  void _paintHoleDimensions(Canvas canvas, _GlassPanel panel, Size size) {
    if (panel.widthMm <= 0 || panel.heightMm <= 0) return;
    final scaleX = panel.rect.width / panel.widthMm;
    final scaleY = panel.rect.height / panel.heightMm;
    final guidePaint = Paint()
      ..color = Colors.deepOrange.shade700.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final textStyle = TextStyle(fontSize: 9, color: Colors.black);

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
      canvas.drawLine(from, to, guidePaint);
      const arrowSize = 5.0;
      final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
      final startHead = Offset(
        from.dx + arrowSize * math.cos(angle - math.pi / 6),
        from.dy + arrowSize * math.sin(angle - math.pi / 6),
      );
      final startHeadOther = Offset(
        from.dx + arrowSize * math.cos(angle + math.pi / 6),
        from.dy + arrowSize * math.sin(angle + math.pi / 6),
      );
      final endHead = Offset(
        to.dx - arrowSize * math.cos(angle - math.pi / 6),
        to.dy - arrowSize * math.sin(angle - math.pi / 6),
      );
      final endHeadOther = Offset(
        to.dx - arrowSize * math.cos(angle + math.pi / 6),
        to.dy - arrowSize * math.sin(angle + math.pi / 6),
      );
      canvas
        ..drawLine(from, startHead, guidePaint)
        ..drawLine(from, startHeadOther, guidePaint)
        ..drawLine(to, endHead, guidePaint)
        ..drawLine(to, endHeadOther, guidePaint);
      drawLabel(label, Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2));
    }

    Offset holeCenter(_GlassHole hole) => Offset(
      panel.rect.left + hole.xMm * scaleX,
      panel.rect.top + hole.yMm * scaleY,
    );

    for (var index = 0; index < panel.holes.length; index++) {
      final hole = panel.holes[index];
      final center = holeCenter(hole);
      final leftMm = hole.xMm.clamp(0.0, panel.widthMm).toDouble();
      final rightMm = (panel.widthMm - hole.xMm)
          .clamp(0.0, panel.widthMm)
          .toDouble();
      final topMm = hole.yMm.clamp(0.0, panel.heightMm).toDouble();
      final bottomMm = (panel.heightMm - hole.yMm)
          .clamp(0.0, panel.heightMm)
          .toDouble();
      final isHorizontallyCentered = (leftMm - rightMm).abs() <= 0.1;
      final isVerticallyCentered = (topMm - bottomMm).abs() <= 0.1;

      // Give every hole its own horizontal and vertical annotation lanes.
      // This keeps the dimensions outside the glass instead of stacking all
      // labels on top of the hole markers.
      final laneOffset = 52.0 + index * 22.0;
      final canUseTopLane = panel.rect.top - laneOffset >= 8;
      final xLaneY = canUseTopLane
          ? panel.rect.top - laneOffset
          : panel.rect.bottom + laneOffset;
      final xExtensionY = canUseTopLane ? panel.rect.top : panel.rect.bottom;

      if (isHorizontallyCentered) {
        drawLabel(centerLabel, Offset(center.dx, xLaneY));
      } else {
        final fromLeft = leftMm <= rightMm;
        final edgeX = fromLeft ? panel.rect.left : panel.rect.right;
        final edgePoint = Offset(edgeX, xExtensionY);
        final centerPoint = Offset(center.dx, xExtensionY);
        canvas
          ..drawLine(Offset(edgeX, center.dy), edgePoint, guidePaint)
          ..drawLine(center, centerPoint, guidePaint);
        drawArrowDimension(
          fromLeft ? edgePoint : centerPoint,
          fromLeft ? centerPoint : edgePoint,
          fromLeft
              ? '← ${leftMm.toStringAsFixed(0)} mm'
              : '→ ${rightMm.toStringAsFixed(0)} mm',
        );
      }

      final neededSideOffset = 34.0 + index * 24.0;
      var yOnLeft = leftMm <= rightMm;
      if (yOnLeft && panel.rect.left - neededSideOffset < 8) yOnLeft = false;
      if (!yOnLeft && panel.rect.right + neededSideOffset > size.width - 8) {
        yOnLeft = true;
      }
      final yLaneX = yOnLeft
          ? panel.rect.left - neededSideOffset
          : panel.rect.right + neededSideOffset;
      final yExtensionX = yOnLeft ? panel.rect.left : panel.rect.right;

      if (isVerticallyCentered) {
        drawLabel(centerLabel, Offset(yLaneX, center.dy));
      } else {
        final fromTop = topMm <= bottomMm;
        final edgeY = fromTop ? panel.rect.top : panel.rect.bottom;
        final edgePoint = Offset(yExtensionX, edgeY);
        final centerPoint = Offset(yExtensionX, center.dy);
        canvas
          ..drawLine(Offset(center.dx, edgeY), edgePoint, guidePaint)
          ..drawLine(center, centerPoint, guidePaint);
        drawArrowDimension(
          fromTop ? edgePoint : centerPoint,
          fromTop ? centerPoint : edgePoint,
          fromTop
              ? '↑ ${topMm.toStringAsFixed(0)} mm'
              : '↓ ${bottomMm.toStringAsFixed(0)} mm',
        );
      }

      drawLabel(
        '#${index + 1} Ø ${hole.diameterMm.toStringAsFixed(0)} mm',
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
    var spacingIndex = 0;
    for (final entry in groupedHoles.entries) {
      if (entry.value.length != 2) continue;
      final first = holeCenter(entry.value[0]);
      final second = holeCenter(entry.value[1]);
      final isHorizontal =
          (second.dx - first.dx).abs() >= (second.dy - first.dy).abs();
      final distanceMm = isHorizontal
          ? (entry.value[1].xMm - entry.value[0].xMm).abs()
          : (entry.value[1].yMm - entry.value[0].yMm).abs();
      final laneOffset = 30.0 + spacingIndex * 18.0;
      spacingIndex++;
      if (isHorizontal) {
        final useTopLane = panel.rect.top - laneOffset >= 8;
        final laneY = useTopLane
            ? panel.rect.top - laneOffset
            : panel.rect.bottom + laneOffset;
        canvas
          ..drawLine(first, Offset(first.dx, laneY), guidePaint)
          ..drawLine(second, Offset(second.dx, laneY), guidePaint);
        drawArrowDimension(
          Offset(first.dx, laneY),
          Offset(second.dx, laneY),
          '${distanceMm.toStringAsFixed(0)} mm',
        );
      } else {
        final useLeftLane = panel.rect.left - laneOffset >= 8;
        final laneX = useLeftLane
            ? panel.rect.left - laneOffset
            : panel.rect.right + laneOffset;
        canvas
          ..drawLine(first, Offset(laneX, first.dy), guidePaint)
          ..drawLine(second, Offset(laneX, second.dy), guidePaint);
        drawArrowDimension(
          Offset(laneX, first.dy),
          Offset(laneX, second.dy),
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
        canvas.drawRect(panel.rect, paint);
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

    for (final band in bands) {
      for (final panel in panels) {
        final scale = panel.rect.height / overallHeightMm;
        final bandRect = Rect.fromLTWH(
          panel.rect.left,
          panel.rect.top + band.offsetMm * scale,
          panel.rect.width,
          band.widthMm * scale,
        ).intersect(panel.rect);
        if (bandRect.width <= 0 || bandRect.height <= 0) continue;
        canvas.drawRect(bandRect, paint);
        canvas.drawRect(bandRect, labelPaint);
      }
    }
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
    final shortSide = panel.width < panel.height ? panel.width : panel.height;
    final inset = (shortSide * 0.04).clamp(2.0, 6.0).toDouble();
    final glassRect = panel.deflate(inset);

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

  bool get isMovable =>
      purpose.startsWith('handle_') || purpose.startsWith('towel_');
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
